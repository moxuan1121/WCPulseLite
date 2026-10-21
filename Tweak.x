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
- (void)removeChatRoomTopMsgLocalWithUserName:(id)userName topId:(id)topId {
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
    if (!WCPLBool(@"WCPLHomeCorner") || ![cell.superview isKindOfClass:%c(MainFrameTableView)]) return;
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
