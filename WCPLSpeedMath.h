// Pure C geometry/rate logic recovered from WCPulse.dylib (WCPlayerView speed gesture).
// Kept free of ObjC so Tests/speed_math_test.c can run it on any host.
#pragma once
#include <math.h>
#include <stdbool.h>

#define WCPL_EDGE_RATIO      0.15   // -[WCPlayerView isEdgeArea:]  width * 0.15
#define WCPL_STEP_PT         24.0   // vertical points per 0.5x step
#define WCPL_STEP_RATE       0.5f
#define WCPL_CANCEL_DX       28.0   // horizontal travel that cancels the gesture
#define WCPL_CANCEL_DX_RATIO 1.15   // ... when |dx| > |dy| * 1.15
#define WCPL_MIN_RATE        0.25f
#define WCPL_MAX_RATE        5.0f

static inline bool WCPLIsEdge(double x, double width) {
    double edge = width * WCPL_EDGE_RATIO;
    return x < edge || x > width - edge;
}

static inline bool WCPLIsLeftEdge(double x, double width) {
    return x < width * WCPL_EDGE_RATIO;
}

static inline bool WCPLShouldCancel(double dx, double dy) {
    return fabs(dx) > WCPL_CANCEL_DX && fabs(dx) > fabs(dy) * WCPL_CANCEL_DX_RATIO;
}

// Signed step count: drag down = positive (faster), drag up = negative.
static inline long WCPLStep(double dy) {
    long n = (long)floor(fabs(dy) / WCPL_STEP_PT);
    if (n <= 0) return 0;
    return dy > 0 ? n : -n;
}

static inline float WCPLRate(float base, long step) {
    float r = (float)step * WCPL_STEP_RATE + base;
    if (r < WCPL_MIN_RATE) r = WCPL_MIN_RATE;
    if (r > WCPL_MAX_RATE) r = WCPL_MAX_RATE;
    return r;
}
