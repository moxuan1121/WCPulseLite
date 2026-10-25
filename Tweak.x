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
            @"WCPLSwipeMsg": @YES,                    // 左滑消息引用/撤回
            @"WCPLTimeFormat": @"MM/dd HH:mm:ss",     // WCPulse default
            @"WCPLEmptyInputVoice": @YES,             // 空输入框长按语音
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
                  @[@"S", @"左滑消息引用/撤回", @"WCPLSwipeMsg"],
                  @[@"T", @"↳ 撤回提示时间格式", @"WCPLTimeFormat"]],
        @[@"输入框", @[@"S", @"空输入框长按语音", @"WCPLEmptyInputVoice"]],
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
    BOOL number = [key isEqualToString:@"WCPLHomeCornerVPadding"];
    BOOL color = [key hasPrefix:@"WCPLHomeCorner"];
    double lo = 0, hi = 50;
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
@property (nonatomic, copy) NSString *m_nsContent, *m_nsFromUsr, *m_nsToUsr, *m_nsRealChatUsr;
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

#pragma mark - 7. 左滑消息 (WCPulse wcpulse_handleSwipeGesture: 0xe672c / onReplyMsg: 0xe8ce4)

// Swipe left on a bubble: others' message -> 引用 / 引用并@ (group only); my message -> 撤回 / 引用.
// Uses WeChat's own cell actions, same as the original: onShowMsgReplyMenuItem:, onRevokeMsg:, longPressOnHeadImage:.
@interface CommonMessageCellView : UIView
- (id)viewModel;
@end

static char kWCPLSwipe;
static void WCPLHaptic(void);

static UIViewController *WCPLOwnerVC(UIView *v) {
    for (UIResponder *r = v; r; r = r.nextResponder)
        if ([r isKindOfClass:%c(BaseMsgContentViewController)]) return (UIViewController *)r;
    return nil;
}

static void WCPLCellAction(id cell, SEL sel) {
    if ([cell respondsToSelector:sel]) ((void (*)(id, SEL, id))objc_msgSend)(cell, sel, nil);
}

%hook CommonMessageCellView
- (void)layoutInternal {
    %orig;
    if (!WCPLBool(@"WCPLSwipeMsg") || objc_getAssociatedObject(self, &kWCPLSwipe)) return;
    UISwipeGestureRecognizer *g = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(wcpl_swiped:)];
    g.direction = UISwipeGestureRecognizerDirectionLeft;
    [self addGestureRecognizer:g];
    objc_setAssociatedObject(self, &kWCPLSwipe, g, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

%new
- (void)wcpl_swiped:(UISwipeGestureRecognizer *)g {
    if (!WCPLBool(@"WCPLSwipeMsg")) return;
    CMessageWrap *msg = [[self viewModel] performSelector:@selector(messageWrap)];
    UIViewController *vc = WCPLOwnerVC(self);
    if (!msg || !vc) return;
    NSString *me = [%c(SettingUtil) performSelector:@selector(getLocalUsrName:) withObject:nil];
    BOOL mine = [msg.m_nsFromUsr isEqualToString:me];
    NSString *realUsr = [msg respondsToSelector:@selector(m_nsRealChatUsr)] ? msg.m_nsRealChatUsr : nil;
    BOOL group = [msg.m_nsFromUsr hasSuffix:@"@chatroom"] || [msg.m_nsToUsr hasSuffix:@"@chatroom"];
    WCPLHaptic();

    if (!mine && !(group && realUsr.length)) { WCPLCellAction(self, @selector(onShowMsgReplyMenuItem:)); return; }

    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:nil message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    __weak id cell = self;
    [sheet addAction:[UIAlertAction actionWithTitle:@"引用" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        WCPLCellAction(cell, @selector(onShowMsgReplyMenuItem:));
    }]];
    if (mine) {
        [sheet addAction:[UIAlertAction actionWithTitle:@"撤回" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
            WCPLCellAction(cell, @selector(onRevokeMsg:));
        }]];
    } else {
        [sheet addAction:[UIAlertAction actionWithTitle:@"引用并@对方" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
            WCPLCellAction(cell, @selector(onShowMsgReplyMenuItem:));
            id contact = [WCPLService(@"CContactMgr") performSelector:@selector(getContactByName:) withObject:realUsr];
            if (contact && [vc respondsToSelector:@selector(longPressOnHeadImage:)])
                [vc performSelector:@selector(longPressOnHeadImage:) withObject:contact];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.sourceView = self;
    [vc presentViewController:sheet animated:YES completion:nil];
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


#pragma mark - 9. 空输入框长按语音 (WCPulse MMTextView 0xa8f48..0xaae90, MMInputToolView 0xd9a3c..0xda640)

// Long-pressing the empty text field records voice, as if holding WeChat's own "按住 说话" button.
// The text view hands its touches to -[MMInputToolView MMTransparentButton_touches*]; recording only
// starts after 0.3s so a quick tap still focuses the keyboard. Unlike WCPulse, the text view keeps its
// normal touch handling until recording actually starts (WCPulse swallowed taps on an empty field).
@interface MMInputToolView : UIView
- (void)MMTransparentButton_touchesBegan:(NSSet *)t withEvent:(UIEvent *)e;
- (void)MMTransparentButton_touchesMoved:(NSSet *)t withEvent:(UIEvent *)e;
- (void)MMTransparentButton_touchesEnded:(NSSet *)t withEvent:(UIEvent *)e;
- (void)MMTransparentButton_touchesCancelled:(NSSet *)t withEvent:(UIEvent *)e;
@end
@interface MMTextView : UITextView
- (id)m_delegate;
- (UILongPressGestureRecognizer *)longPressGesture;
@end

static char kVoicePending, kVoiceActive, kVoiceDisabledGR;
static BOOL gVoiceBlockMode2;   // WCPulse 0xa25e48: for 2s after recording, keep WeChat out of input mode 2

// 0x11f130: empty after removing zero-width chars and whitespace.
static BOOL WCPLTextEmpty(NSString *s) {
    if (![s isKindOfClass:NSString.class] || !s.length) return YES;
    s = [[s stringByReplacingOccurrencesOfString:@"\u200b" withString:@""] stringByReplacingOccurrencesOfString:@"\ufeff" withString:@""];
    return [s stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length == 0;
}

// m_delegate is MMGrowTextView, whose m_delegate is MMInputToolView.
static MMInputToolView *WCPLToolView(MMTextView *tv) {
    id d = [tv respondsToSelector:@selector(m_delegate)] ? [tv m_delegate] : nil;
    if ([d isKindOfClass:%c(MMGrowTextView)] && [d respondsToSelector:@selector(m_delegate)]) d = [d m_delegate];
    return [d respondsToSelector:@selector(MMTransparentButton_touchesBegan:withEvent:)] ? d : nil;
}

static void WCPLVoiceCancelPending(MMTextView *tv) {
    dispatch_block_t b = objc_getAssociatedObject(tv, &kVoicePending);
    if (b) dispatch_block_cancel(b);
    objc_setAssociatedObject(tv, &kVoicePending, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void WCPLVoiceRestoreGestures(MMTextView *tv) {
    for (UIGestureRecognizer *g in tv.gestureRecognizers) {
        if (![objc_getAssociatedObject(g, &kVoiceDisabledGR) boolValue]) continue;
        g.enabled = YES;
        objc_setAssociatedObject(g, &kVoiceDisabledGR, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

%hook MMTextView
// 0xa8f48: the text loupe must not start before our 0.3s voice delay.
- (UILongPressGestureRecognizer *)longPressGesture {
    UILongPressGestureRecognizer *g = %orig;
    if (WCPLBool(@"WCPLEmptyInputVoice") && g.minimumPressDuration < 0.5) g.minimumPressDuration = 0.5;
    return g;
}

// 0xa9b0c: no loupe/select menu on an empty field.
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)g {
    if (WCPLBool(@"WCPLEmptyInputVoice") && [self respondsToSelector:@selector(longPressGesture)] &&
        g == [self longPressGesture] && WCPLTextEmpty(self.text)) return NO;
    return %orig;
}

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event {
    %orig;
    if (!WCPLBool(@"WCPLEmptyInputVoice") || touches.count != 1 || !WCPLTextEmpty(self.text)) return;
    if ([objc_getAssociatedObject(self, &kVoiceActive) boolValue] || !WCPLToolView(self)) return;
    WCPLVoiceCancelPending(self);
    __weak MMTextView *weakSelf = self;
    dispatch_block_t start = dispatch_block_create(0, ^{
        MMTextView *tv = weakSelf;
        if (!tv) return;
        objc_setAssociatedObject(tv, &kVoicePending, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        MMInputToolView *tool = WCPLToolView(tv);
        if (!tool || !WCPLTextEmpty(tv.text)) return;
        objc_setAssociatedObject(tv, &kVoiceActive, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if (tv.isFirstResponder) [tv resignFirstResponder];
        // 0xaa1c8: disabling cancels the text view's own tap/loupe gestures for this touch.
        for (UIGestureRecognizer *g in tv.gestureRecognizers) {
            if (!g.enabled) continue;
            g.enabled = NO;
            objc_setAssociatedObject(g, &kVoiceDisabledGR, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        [tool MMTransparentButton_touchesBegan:touches withEvent:event];
    });
    objc_setAssociatedObject(self, &kVoicePending, start, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), start);
}

- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event {
    if (![objc_getAssociatedObject(self, &kVoiceActive) boolValue]) {
        %orig;
        return;
    }
    [WCPLToolView(self) MMTransparentButton_touchesMoved:touches withEvent:event];
}

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event {
    WCPLVoiceCancelPending(self);
    if (![objc_getAssociatedObject(self, &kVoiceActive) boolValue]) {
        %orig;
        return;
    }
    objc_setAssociatedObject(self, &kVoiceActive, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    WCPLVoiceRestoreGestures(self);
    [WCPLToolView(self) MMTransparentButton_touchesEnded:touches withEvent:event];
    gVoiceBlockMode2 = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        gVoiceBlockMode2 = NO;
    });
}

- (void)touchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event {
    WCPLVoiceCancelPending(self);
    if (![objc_getAssociatedObject(self, &kVoiceActive) boolValue]) {
        %orig;
        return;
    }
    objc_setAssociatedObject(self, &kVoiceActive, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    WCPLVoiceRestoreGestures(self);
    [WCPLToolView(self) MMTransparentButton_touchesCancelled:touches withEvent:event];
}
%end

%hook MMInputToolView
// 0xda640: right after a voice send WeChat switches to mode 2; WCPulse keeps mode 1 instead.
- (void)setInputMode:(long long)mode animated:(BOOL)animated {
    if (gVoiceBlockMode2 && mode == 2) {
        %orig(1, animated);
        return;
    }
    %orig;
}
%end
