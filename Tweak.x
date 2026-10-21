// WCPulseLite — WeChat features extracted from WCPulse.dylib (sections 1-3) and WCPush2Chat.dylib (section 4).
// Each block below names the original function address it mirrors.
#import <UIKit/UIKit.h>
#import <UserNotifications/UserNotifications.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "WCPLSpeedMath.h"

#pragma mark - Settings (defaults = user's requested values)

static NSUserDefaults *WCPLDefaults(void) {
    static NSUserDefaults *d;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        d = [NSUserDefaults standardUserDefaults];
        [d registerDefaults:@{
            @"WCPLTopClickKeep": @YES,
            @"WCPLHomeCorner": @YES,
            @"WCPLHomeCornerVPadding": @8.0,          // WCPulse default 8.0
            @"WCPLHomeCornerLight": @"#F7F7F7",       // WCPulse default 0.969 gray
            @"WCPLHomeCornerDark": @"#191919",        // WCPulse default 0.098 gray
            @"WCPLVideoSpeed": @YES,
            @"WCPLLeftSpeed": @"2.0x",                // WCPulse default 0.5x; user wants 2.0x
            @"WCPLRightSpeed": @"2.0x",
            @"WCPLPushFG": @YES,                      // 前台直达
            @"WCPLPushBG": @YES,                      // 后台直达
            @"WCPLPushFGMode": @0,                    // 0 全屏 / 1 半屏
            @"WCPLPushBGMode": @0,
            @"WCPLNoRevoke": @YES,                    // 防撤回
            @"WCPLTimeLabel": @YES,                   // 消息具体时间
            @"WCPLTimeFormat": @"MM/dd HH:mm:ss",     // WCPulse default
            @"WCPLTimeFontSize": @7.0,                // WCPulse default
            @"WCPLTimeColor": @"#8E8E93",             // light mode
            @"WCPLTimeColorDark": @"#8E8E93",
        }];
    });
    return d;
}
static BOOL WCPLBool(NSString *k) { return [WCPLDefaults() boolForKey:k]; }

static UIColor *WCPLHex(NSString *hex) {
    unsigned v = 0;
    [[NSScanner scannerWithString:[hex stringByReplacingOccurrencesOfString:@"#" withString:@""]] scanHexInt:&v];
    return [UIColor colorWithRed:((v >> 16) & 0xFF) / 255.0 green:((v >> 8) & 0xFF) / 255.0 blue:(v & 0xFF) / 255.0 alpha:1];
}

#pragma mark - 1. 置顶点击保留 (0xc27c0 / 0xc2894)

// Tapping the pinned-message bar makes WeChat drop the pin locally.
// WCPulse opens a 2.5s window on tap and swallows the local removal inside it.
static CFTimeInterval gTopKeepDeadline;

%hook RoomContentLogicController
- (void)OnClickTopMessageTipsBar:(id)bar {
    if (WCPLBool(@"WCPLTopClickKeep")) gTopKeepDeadline = CACurrentMediaTime() + 2.5;
    %orig;
}
%end

%hook CGroupMgr
// topId is an integer (original only storeStrong's userName); typing it `id` made ARC retain 0x1a5 -> crash.
- (void)removeChatRoomTopMsgLocalWithUserName:(id)userName topId:(unsigned long long)topId {
    if (WCPLBool(@"WCPLTopClickKeep") && CACurrentMediaTime() < gTopKeepDeadline) return;
    %orig;
}
%end

#pragma mark - 2. 首页圆角 (0x1c1928 / 0x1c1d4c / 0x1c21e0 / 0x1c2d08..0x1c2fa8)

@interface MainFrameTableView : UITableView @end

static CGFloat WCPLPad(void) { return [WCPLDefaults() doubleForKey:@"WCPLHomeCornerVPadding"]; }

%hook MainFrameTableView
// The "corner" is UITableViewStyleInsetGrouped; padding drives header/footer/insets.
- (id)initWithFrame:(CGRect)frame style:(UITableViewStyle)style {
    if (!WCPLBool(@"WCPLHomeCorner")) return %orig;
    MainFrameTableView *t = %orig(frame, UITableViewStyleInsetGrouped);
    CGFloat pad = WCPLPad();
    t.sectionHeaderHeight = pad;
    t.sectionFooterHeight = pad;
    t.contentInset = UIEdgeInsetsMake(pad, 0, pad, 0);
    t.scrollIndicatorInsets = UIEdgeInsetsMake(pad, 0, pad, 0);
    if (@available(iOS 15.0, *)) t.sectionHeaderTopPadding = pad;
    return t;
}
- (CGFloat)tableView:(UITableView *)tv heightForHeaderInSection:(NSInteger)section {
    return WCPLBool(@"WCPLHomeCorner") ? WCPLPad() : %orig;
}
%end

%hook MMTableViewCell
- (void)layoutSubviews {
    %orig;
    UITableViewCell *cell = (UITableViewCell *)self;
    // Original (0x1c2280..0x1c2318) checks cell.superview.superview, not cell.superview.
    if (!WCPLBool(@"WCPLHomeCorner") || ![cell.superview.superview isKindOfClass:%c(MainFrameTableView)]) return;
    BOOL dark = UITraitCollection.currentTraitCollection.userInterfaceStyle == UIUserInterfaceStyleDark;
    cell.backgroundColor = WCPLHex([WCPLDefaults() stringForKey:dark ? @"WCPLHomeCornerDark" : @"WCPLHomeCornerLight"]);
    // Plain UIView children are WeChat's opaque backdrops; clear them so the cell color shows.
    for (UIView *v in cell.subviews)
        if (v.class == UIView.class) v.backgroundColor = UIColor.clearColor;
}
%end

// Header rows on the home list (web / favorites / banner) get transparent backgrounds.
// (Logos runs before cpp, so these can't share a macro.)
static void WCPLClearBG(id view) {
    if (WCPLBool(@"WCPLHomeCorner")) ((UIView *)view).backgroundColor = UIColor.clearColor;
}
%hook MFWebMMBtn
- (void)layoutSubviews {
    %orig;
    WCPLClearBG(self);
}
%end
%hook MMFavCellComponent
- (void)layoutSubviews {
    %orig;
    WCPLClearBG(self);
}
%end
%hook MMFavImageComponent
- (void)layoutSubviews {
    %orig;
    WCPLClearBG(self);
}
%end
%hook MFBannerBtn
- (void)layoutSubviews {
    %orig;
    WCPLClearBG(self);
}
%end

#pragma mark - 4. 消息直达 (WCPush2Chat 0x4bbc / 0x4e28 / 0x5530 / 0x5974)

// Tapping a message notification opens that chat directly (full-screen push or half-screen sheet).
@interface CContact : NSObject
@property (nonatomic, copy) NSString *m_nsUsrName;
@end
@interface BaseMsgContentViewController : UIViewController
- (CContact *)getChatContact;
@end

static id WCPLService(NSString *name) {
    id center = [[%c(MMContext) performSelector:@selector(currentContext)] performSelector:@selector(serviceCenter)];
    return [center performSelector:@selector(getService:) withObject:NSClassFromString(name)];
}

static UIViewController *WCPLTopVC(void) {
    UIViewController *vc = UIApplication.sharedApplication.keyWindow.rootViewController;
    for (;;) {
        if (vc.presentedViewController) vc = vc.presentedViewController;
        else if ([vc isKindOfClass:UITabBarController.class]) vc = ((UITabBarController *)vc).selectedViewController;
        else if ([vc isKindOfClass:UINavigationController.class]) vc = ((UINavigationController *)vc).visibleViewController;
        else return vc;
    }
}

static void WCPLOpenChat(CContact *contact, UIViewController *vc, BOOL foreground) {
    BOOL half = [WCPLDefaults() integerForKey:foreground ? @"WCPLPushFGMode" : @"WCPLPushBGMode"] == 1;
    if (half)
        [WCPLService(@"QuickReplyMsgMgr") performSelector:@selector(showPageSheetSession:fromViewController:) withObject:contact withObject:vc];
    else
        ((void (*)(id, SEL, id, id, BOOL))objc_msgSend)(WCPLService(@"MMMsgLogicManager"),
            @selector(PushOtherBaseMsgControllerByContact:navigationController:animated:), contact, vc.navigationController, YES);
}

// UI may not be ready right after a cold launch: retry every 0.5s, give up after 10 tries (as the original).
static void WCPLPushToChat(UNNotificationResponse *response, BOOL foreground) {
    NSString *user = response.notification.request.content.userInfo[@"u"];
    if (![user isKindOfClass:NSString.class]) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        CContact *contact = [WCPLService(@"CContactMgr") performSelector:@selector(getContactByName:) withObject:user];
        if (!contact) return;
        __block int tries = 0;
        [NSTimer scheduledTimerWithTimeInterval:0.5 repeats:YES block:^(NSTimer *t) {
            UIViewController *top = WCPLTopVC();
            if (!top.navigationController) { if (++tries >= 10) [t invalidate]; return; }
            [t invalidate];
            if (foreground && [top isKindOfClass:%c(BaseMsgContentViewController)] &&
                [[(BaseMsgContentViewController *)top getChatContact].m_nsUsrName isEqualToString:user]) return;
            WCPLOpenChat(contact, top, foreground);
        }];
    });
}

%hook MicroMessengerAppDelegate
- (void)userNotificationCenter:(id)c didReceiveNotificationResponse:(UNNotificationResponse *)r withCompletionHandler:(id)h {
    if (WCPLBool(@"WCPLPushBG")) WCPLPushToChat(r, NO);
    %orig;
}
%end

%hook NotificationActionsMgr
- (void)userNotificationCenter:(id)c didReceiveNotificationResponse:(UNNotificationResponse *)r withCompletionHandler:(id)h {
    if (WCPLBool(@"WCPLPushFG")) WCPLPushToChat(r, YES);
    %orig;
}
%end

#pragma mark - 5. 设置页 (entry mirrors WCPush2Chat 0x527c / 0x5498)

// Row kinds: S = switch, T = text (alert input), M = 全屏/半屏 segment.
static NSArray<NSArray *> *WCPLRows(void) {
    return @[
        @[@"置顶", @[@"S", @"启用置顶点击保留", @"WCPLTopClickKeep"]],
        @[@"首页圆角（重启微信生效）", @[@"S", @"启用首页圆角", @"WCPLHomeCorner"],
                                     @[@"T", @"↳ 上下间距", @"WCPLHomeCornerVPadding"],
                                     @[@"T", @"↳ 背景颜色", @"WCPLHomeCornerLight"],
                                     @[@"T", @"↳ 深色背景颜色", @"WCPLHomeCornerDark"]],
        @[@"视频", @[@"S", @"启用视频倍速手势", @"WCPLVideoSpeed"],
                  @[@"T", @"↳ 左侧倍速", @"WCPLLeftSpeed"],
                  @[@"T", @"↳ 右侧倍速", @"WCPLRightSpeed"]],
        @[@"消息", @[@"S", @"启用防撤回", @"WCPLNoRevoke"],
                  @[@"S", @"显示消息具体时间", @"WCPLTimeLabel"],
                  @[@"T", @"↳ 时间格式", @"WCPLTimeFormat"],
                  @[@"T", @"↳ 时间字号", @"WCPLTimeFontSize"],
                  @[@"T", @"↳ 时间颜色", @"WCPLTimeColor"],
                  @[@"T", @"↳ 深色时间颜色", @"WCPLTimeColorDark"]],
        @[@"消息直达", @[@"S", @"开启前台直达", @"WCPLPushFG"],
                    @[@"M", @"↳ 前台直达模式", @"WCPLPushFGMode"],
                    @[@"S", @"开启后台直达", @"WCPLPushBG"],
                    @[@"M", @"↳ 后台直达模式", @"WCPLPushBGMode"]],
    ];
}

@interface WCPLSettingsVC : UITableViewController
@end

@implementation WCPLSettingsVC
- (instancetype)init {
    if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) self.title = @"WCPulseLite";
    return self;
}
- (NSArray *)row:(NSIndexPath *)ip { return WCPLRows()[ip.section][ip.row + 1]; }
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return WCPLRows().count; }
- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s { return WCPLRows()[s].count - 1; }
- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s { return WCPLRows()[s][0]; }

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    NSArray *r = [self row:ip];
    NSString *kind = r[0], *key = r[2];
    UITableViewCell *c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
    c.textLabel.text = r[1];
    c.selectionStyle = UITableViewCellSelectionStyleNone;
    if ([kind isEqualToString:@"S"]) {
        UISwitch *sw = [UISwitch new];
        sw.on = [WCPLDefaults() boolForKey:key];
        sw.accessibilityIdentifier = key;
        [sw addTarget:self action:@selector(toggled:) forControlEvents:UIControlEventValueChanged];
        c.accessoryView = sw;
    } else if ([kind isEqualToString:@"M"]) {
        UISegmentedControl *seg = [[UISegmentedControl alloc] initWithItems:@[@"全屏", @"半屏"]];
        seg.selectedSegmentIndex = [WCPLDefaults() integerForKey:key];
        seg.accessibilityIdentifier = key;
        [seg addTarget:self action:@selector(segmented:) forControlEvents:UIControlEventValueChanged];
        c.accessoryView = seg;
    } else {
        c.detailTextLabel.text = [WCPLDefaults() objectForKey:key] ? [[WCPLDefaults() objectForKey:key] description] : @"";
        c.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        c.selectionStyle = UITableViewCellSelectionStyleDefault;
    }
    return c;
}

- (void)toggled:(UISwitch *)sw { [WCPLDefaults() setBool:sw.on forKey:sw.accessibilityIdentifier]; }
- (void)segmented:(UISegmentedControl *)s { [WCPLDefaults() setInteger:s.selectedSegmentIndex forKey:s.accessibilityIdentifier]; }

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    NSArray *r = [self row:ip];
    if (![r[0] isEqualToString:@"T"]) return;
    NSString *key = r[2];
    BOOL fontSize = [key isEqualToString:@"WCPLTimeFontSize"];
    BOOL number = fontSize || [key isEqualToString:@"WCPLHomeCornerVPadding"];
    BOOL color = [key hasPrefix:@"WCPLHomeCorner"] || [key hasPrefix:@"WCPLTimeColor"];
    double lo = fontSize ? 4 : 0, hi = fontSize ? 20 : 50;
    UIAlertController *a = [UIAlertController alertControllerWithTitle:r[1]
        message:number ? [NSString stringWithFormat:@"%.1f - %.1f", lo, hi] : (color ? @"十六进制颜色，如 #F7F7F7" :
                 [key isEqualToString:@"WCPLTimeFormat"] ? @"如 MM/dd HH:mm:ss" : @"如 2.0x")
        preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *f) {
        f.text = [[WCPLDefaults() objectForKey:key] description];
        if (number) f.keyboardType = UIKeyboardTypeDecimalPad;
    }];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
        NSString *v = [a.textFields.firstObject.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        if (number) [WCPLDefaults() setDouble:MIN(MAX(v.doubleValue, lo), hi) forKey:key];
        else if (v.length) [WCPLDefaults() setObject:v forKey:key];
        [tv reloadRowsAtIndexPaths:@[ip] withRowAnimation:UITableViewRowAnimationNone];
    }]];
    [self presentViewController:a animated:YES completion:nil];
}
@end

@interface NewSettingViewController : UIViewController
@end

%hook NewSettingViewController
- (void)reloadTableData {
    %orig;
    Ivar iv = class_getInstanceVariable(object_getClass(self), "m_tableViewMgr");
    id mgr = iv ? object_getIvar(self, iv) : nil;
    if (!mgr) return;
    id section = [%c(WCTableViewSectionManager) performSelector:@selector(defaultSection)];
    id cell = ((id (*)(id, SEL, SEL, id, id, id, BOOL))objc_msgSend)(%c(WCTableViewNormalCellManager),
        @selector(normalCellForSel:target:title:rightValue:canRightValueCopy:),
        @selector(wcpl_openSettings), self, @"WCPulseLite", @"", NO);
    [section performSelector:@selector(addCell:) withObject:cell];
    ((void (*)(id, SEL, id, NSUInteger))objc_msgSend)(mgr, @selector(insertSection:At:), section, 0);
    [[mgr performSelector:@selector(getTableView)] reloadData];
}

%new
- (void)wcpl_openSettings {
    [self.navigationController pushViewController:[WCPLSettingsVC new] animated:YES];
}
%end

#pragma mark - 6. 防撤回 (WCPulse -[MessageRevokeMgr onRevokeMsg:] 0x10588c)

// Instead of letting WeChat delete the message, keep it and insert a local system note after it.
@interface CMessageWrap : NSObject
- (instancetype)initWithMsgType:(long long)type;
@property (nonatomic, copy) NSString *m_nsContent, *m_nsFromUsr, *m_nsToUsr;
@property (nonatomic) unsigned int m_uiCreateTime, m_uiStatus;
@end

static NSString *WCPLXMLValue(NSString *xml, NSString *tag) {
    NSRange a = [xml rangeOfString:[NSString stringWithFormat:@"<%@>", tag]];
    NSRange b = [xml rangeOfString:[NSString stringWithFormat:@"</%@>", tag]];
    if (a.location == NSNotFound || b.location == NSNotFound || b.location < NSMaxRange(a)) return nil;
    NSString *v = [xml substringWithRange:NSMakeRange(NSMaxRange(a), b.location - NSMaxRange(a))];
    if ([v hasPrefix:@"<![CDATA["] && [v hasSuffix:@"]]>"]) v = [v substringWithRange:NSMakeRange(9, v.length - 12)];
    return v;
}

static NSString *WCPLFormatTime(unsigned int t) {
    NSDateFormatter *f = [NSDateFormatter new];
    f.dateFormat = [WCPLDefaults() stringForKey:@"WCPLTimeFormat"];
    return [f stringFromDate:[NSDate dateWithTimeIntervalSince1970:t]];
}

%hook MessageRevokeMgr
- (void)onRevokeMsg:(CMessageWrap *)wrap {
    if (!WCPLBool(@"WCPLNoRevoke")) {
        %orig;
        return;
    }
    NSString *xml = wrap.m_nsContent, *session = WCPLXMLValue(xml, @"session") ?: wrap.m_nsFromUsr;
    NSString *svrID = WCPLXMLValue(xml, @"newmsgid"), *replace = WCPLXMLValue(xml, @"replacemsg") ?: @"";
    id msgMgr = WCPLService(@"CMessageMgr");
    CMessageWrap *orig = svrID ? ((id (*)(id, SEL, id, long long))objc_msgSend)(msgMgr, @selector(GetMsg:n64SvrID:), session, svrID.longLongValue) : nil;
    // My own revokes ("你撤回了一条消息") and unknown messages go through normally.
    if (!orig || [replace hasPrefix:@"你"]) {
        %orig;
        return;
    }

    NSString *name = [[replace componentsSeparatedByString:@"撤回了"].firstObject
        stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"\"“” "]];
    CMessageWrap *note = [[%c(CMessageWrap) alloc] initWithMsgType:10000];   // system tip
    note.m_nsFromUsr = orig.m_nsFromUsr;
    note.m_nsToUsr = orig.m_nsToUsr;
    note.m_uiStatus = 4;
    note.m_uiCreateTime = orig.m_uiCreateTime + 1;
    note.m_nsContent = [NSString stringWithFormat:@"%@ 已拦截%@撤回的消息", WCPLFormatTime(orig.m_uiCreateTime), name.length ? name : @"对方"];
    ((void (*)(id, SEL, id, id, BOOL, BOOL))objc_msgSend)(msgMgr, @selector(AddLocalMsg:MsgWrap:fixTime:NewMsgArriveNotify:), session, note, YES, NO);
}
%end

#pragma mark - 7. 消息具体时间 (WCPulse -[CommonMessageCellView wcpulse_setupTimeLabelAndGesture] 0xe4630)

// Small label under each avatar with the message's send time (font 7, width = 6x font, height = 1.5x font).
@interface CommonMessageCellView : UIView
- (id)viewModel;
- (UIView *)getHeadImageView;
@end

static const NSInteger kWCPLTimeTag = 10087;   // original tag

%hook CommonMessageCellView
- (void)layoutInternal {
    %orig;
    UIView *head = [self getHeadImageView];
    UILabel *label = (UILabel *)[self viewWithTag:kWCPLTimeTag];
    CMessageWrap *msg = [[self viewModel] performSelector:@selector(messageWrap)];
    if (!WCPLBool(@"WCPLTimeLabel") || !head || head.hidden || !msg) { label.hidden = YES; return; }
    if (!label) {
        label = [UILabel new];
        label.tag = kWCPLTimeTag;
        label.textAlignment = NSTextAlignmentCenter;
        label.adjustsFontSizeToFitWidth = YES;
        label.minimumScaleFactor = 0.5;
        [self addSubview:label];
    }
    CGFloat size = [WCPLDefaults() doubleForKey:@"WCPLTimeFontSize"];
    BOOL dark = self.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark;
    label.font = [UIFont systemFontOfSize:size];
    label.textColor = WCPLHex([WCPLDefaults() stringForKey:dark ? @"WCPLTimeColorDark" : @"WCPLTimeColor"]);
    // Original geometry: width = 6 x font size, height = 1.5 x font size, under the avatar.
    CGRect h = [self convertRect:head.bounds fromView:head];
    label.frame = CGRectMake(CGRectGetMidX(h) - size * 3, CGRectGetMaxY(h) + 1, size * 6, size * 1.5);
    label.text = WCPLFormatTime(msg.m_uiCreateTime);
    label.hidden = NO;
}
%end

#pragma mark - 3. 视频倍速手势 (0x9b2cc / 0x9b6dc / 0x9c884 / 0x116000)

@interface WCPlayerView : UIView
- (void)setPlayBackRate:(float)rate;
@end

@interface WXFullScreenGestureRecognizer : UIGestureRecognizer
- (CGPoint)touchBeginPoint;
@end

static char kGesture, kDelegate, kBaseRate, kStartPoint, kLastStep;

#pragma mark Speed HUD (SpeedFloatView: dark blur, 12pt radius, white bold 13pt, 130x28 at y=70)

@interface WCPLSpeedHUD : UIView
@property (nonatomic, strong) UILabel *label;
@property (nonatomic, strong) UIView *arrows;
+ (instancetype)shared;
- (void)showSpeed:(float)rate left:(BOOL)left;
- (void)hide;
@end

@implementation WCPLSpeedHUD
+ (instancetype)shared {
    static WCPLSpeedHUD *h;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ h = [[self alloc] initWithFrame:CGRectMake(0, 0, 130, 28)]; });
    return h;
}
- (instancetype)initWithFrame:(CGRect)f {
    if (!(self = [super initWithFrame:f])) return nil;
    self.alpha = 0;
    self.layer.cornerRadius = 12;
    self.clipsToBounds = YES;
    self.userInteractionEnabled = NO;
    UIVisualEffectView *blur = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleDark]];
    blur.frame = self.bounds;
    blur.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self addSubview:blur];
    _arrows = [[UIView alloc] initWithFrame:CGRectMake(10, 9, 24, 10)];
    for (int i = 0; i < 3; i++) {
        CAShapeLayer *tri = [CAShapeLayer layer];
        UIBezierPath *p = [UIBezierPath bezierPath];
        [p moveToPoint:CGPointMake(0, 0)];
        [p addLineToPoint:CGPointMake(7, 5)];
        [p addLineToPoint:CGPointMake(0, 10)];
        [p closePath];
        tri.path = p.CGPath;
        tri.fillColor = UIColor.whiteColor.CGColor;
        tri.position = CGPointMake(i * 8, 0);
        [_arrows.layer addSublayer:tri];
    }
    [self addSubview:_arrows];
    _label = [[UILabel alloc] initWithFrame:CGRectMake(34, 0, 90, 28)];
    _label.textColor = UIColor.whiteColor;
    _label.font = [UIFont systemFontOfSize:13 weight:UIFontWeightBold];
    _label.textAlignment = NSTextAlignmentCenter;
    [self addSubview:_label];
    return self;
}
- (void)showSpeed:(float)rate left:(BOOL)left {
    self.label.text = [NSString stringWithFormat:@"%.1fx倍速", rate];
    self.arrows.transform = left ? CGAffineTransformMakeScale(-1, 1) : CGAffineTransformIdentity;
    UIView *host = UIApplication.sharedApplication.keyWindow;
    if (!host) return;
    if (self.superview != host) [host addSubview:self];
    self.center = CGPointMake(CGRectGetMidX(host.bounds), 70);
    [host bringSubviewToFront:self];
    if (self.alpha < 1) {
        CABasicAnimation *blink = [CABasicAnimation animationWithKeyPath:@"opacity"];
        blink.fromValue = @1; blink.toValue = @0.3; blink.duration = 0.5;
        blink.autoreverses = YES; blink.repeatCount = HUGE_VALF;
        [self.arrows.layer addAnimation:blink forKey:@"blink"];
        [UIView animateWithDuration:0.2 animations:^{ self.alpha = 1; }];
    }
}
- (void)hide {
    if (!self.superview || self.alpha == 0) return;
    [UIView animateWithDuration:0.2 animations:^{ self.alpha = 0; } completion:^(BOOL done) {
        if (self.alpha == 0) { [self.arrows.layer removeAllAnimations]; [self removeFromSuperview]; }
    }];
}
@end

static void WCPLHaptic(void) {
    [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight] impactOccurred];
}

static float WCPLSideRate(BOOL left) {
    NSString *s = [WCPLDefaults() stringForKey:left ? @"WCPLLeftSpeed" : @"WCPLRightSpeed"];
    return [[s stringByReplacingOccurrencesOfString:@"x" withString:@""] floatValue];
}

// 0x116000: restore 1.0x, hide HUD, clear gesture state.
static void WCPLResetSpeed(WCPlayerView *player) {
    if (objc_getAssociatedObject(player, &kBaseRate)) {
        [player setPlayBackRate:1.0f];
        [[WCPLSpeedHUD shared] hide];
    }
    objc_setAssociatedObject(player, &kBaseRate, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(player, &kStartPoint, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(player, &kLastStep, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

// 0x850a4: every other non tap/pinch/rotation recognizer on the player and its ancestors waits for ours.
static void WCPLPrioritize(UIView *view, UIGestureRecognizer *ours) {
    if (!view || !ours) return;
    for (UIView *v = view; v; v = v.superview)
        for (UIGestureRecognizer *g in [v.gestureRecognizers copy])
            if (g != ours && ![g isKindOfClass:UITapGestureRecognizer.class] &&
                ![g isKindOfClass:UIPinchGestureRecognizer.class] && ![g isKindOfClass:UIRotationGestureRecognizer.class])
                [g requireGestureRecognizerToFail:ours];
}

@interface WCPLSpeedGestureDelegate : NSObject <UIGestureRecognizerDelegate> @end
@implementation WCPLSpeedGestureDelegate
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gr shouldReceiveTouch:(UITouch *)touch {
    UIView *v = gr.view;
    if ([v isKindOfClass:%c(WCPlayerView)]) WCPLPrioritize(v, gr);
    return v && WCPLIsEdge([touch locationInView:v].x, v.bounds.size.width);
}
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gr shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)other {
    Class fs = %c(WXFullScreenGestureRecognizer);
    if (fs && [other isKindOfClass:fs]) return NO;
    if ([other isKindOfClass:UIPanGestureRecognizer.class]) {
        CGPoint v = [(UIPanGestureRecognizer *)other velocityInView:other.view];
        if (fabs(v.y) > fabs(v.x)) return NO;
    }
    return ![other isKindOfClass:UILongPressGestureRecognizer.class];
}
@end

%hook WCPlayerView
- (void)layoutSubviews {
    %orig;
    UILongPressGestureRecognizer *g = objc_getAssociatedObject(self, &kGesture);
    BOOL on = WCPLBool(@"WCPLVideoSpeed");
    if (on && !g) {
        WCPLSpeedGestureDelegate *del = [WCPLSpeedGestureDelegate new];
        g = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(wcpl_handleSpeedPress:)];
        g.cancelsTouchesInView = NO;
        g.delaysTouchesBegan = NO;
        g.delaysTouchesEnded = NO;
        g.numberOfTouchesRequired = 1;
        g.delegate = del;
        objc_setAssociatedObject(self, &kDelegate, del, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(self, &kGesture, g, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [self addGestureRecognizer:g];
    } else if (!on && g) {
        WCPLResetSpeed(self);
        [self removeGestureRecognizer:g];
        objc_setAssociatedObject(self, &kGesture, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(self, &kDelegate, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        g = nil;
    }
    if (on && g) WCPLPrioritize(self, g);
}

%new
- (void)wcpl_handleSpeedPress:(UILongPressGestureRecognizer *)gr {
    if (!WCPLBool(@"WCPLVideoSpeed")) { WCPLResetSpeed(self); return; }
    CGPoint loc = [gr locationInView:self];
    CGFloat width = self.bounds.size.width;

    if (gr.state == UIGestureRecognizerStateBegan) {
        if (!WCPLIsEdge(loc.x, width)) return;
        BOOL left = WCPLIsLeftEdge(loc.x, width);
        float rate = WCPLSideRate(left);
        WCPLHaptic();
        [self setPlayBackRate:rate];
        [[WCPLSpeedHUD shared] showSpeed:rate left:left];
        objc_setAssociatedObject(self, &kBaseRate, @(rate), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(self, &kStartPoint, [NSValue valueWithCGPoint:loc], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(self, &kLastStep, @0, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return;
    }
    if (gr.state == UIGestureRecognizerStateChanged) {
        NSNumber *base = objc_getAssociatedObject(self, &kBaseRate);
        NSValue *start = objc_getAssociatedObject(self, &kStartPoint);
        NSNumber *last = objc_getAssociatedObject(self, &kLastStep);
        if (!base || !start) return;
        CGPoint s = start.CGPointValue;
        double dx = loc.x - s.x, dy = loc.y - s.y;
        if (gr.numberOfTouches != 1 || WCPLShouldCancel(dx, dy)) {
            WCPLResetSpeed(self);
            gr.enabled = NO;   // cancel, then re-arm
            gr.enabled = YES;
            return;
        }
        long step = WCPLStep(dy);
        if (last && last.longValue == step) return;
        float rate = WCPLRate(base.floatValue, step);
        [self setPlayBackRate:rate];
        [[WCPLSpeedHUD shared] showSpeed:rate left:WCPLIsLeftEdge(loc.x, width)];
        WCPLHaptic();
        objc_setAssociatedObject(self, &kLastStep, @(step), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return;
    }
    if (gr.state == UIGestureRecognizerStateEnded || gr.state == UIGestureRecognizerStateCancelled ||
        gr.state == UIGestureRecognizerStateFailed)
        WCPLResetSpeed(self);
}
%end

// WeChat's own full-screen long press (menu) must not fire inside the 15% edge zones.
%hook WXFullScreenGestureRecognizer
- (void)LongPressEvents {
    if (!WCPLBool(@"WCPLVideoSpeed")) {
        %orig;
        return;
    }
    UIView *v = ((UIGestureRecognizer *)self).view;
    if (v && WCPLIsEdge([self touchBeginPoint].x, v.bounds.size.width)) return;
    %orig;
}
%end
