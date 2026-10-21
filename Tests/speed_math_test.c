#include <stdio.h>
#include "../WCPLSpeedMath.h"

static int fails;
#define CHECK(c) do { if (!(c)) { printf("FAIL %s:%d %s\n", __FILE__, __LINE__, #c); fails++; } } while (0)

int main(void) {
    // 15% edge zones on a 400pt-wide player.
    CHECK(WCPLIsEdge(10, 400));
    CHECK(WCPLIsEdge(395, 400));
    CHECK(!WCPLIsEdge(200, 400));
    CHECK(WCPLIsLeftEdge(59, 400));
    CHECK(!WCPLIsLeftEdge(61, 400));

    CHECK(WCPLStep(0) == 0);
    CHECK(WCPLStep(23.9) == 0);
    CHECK(WCPLStep(24) == 1);
    CHECK(WCPLStep(-50) == -2);

    CHECK(WCPLRate(2.0f, 1) == 2.5f);
    CHECK(WCPLRate(2.0f, -10) == 0.25f);
    CHECK(WCPLRate(2.0f, 10) == 5.0f);

    CHECK(WCPLShouldCancel(30, 10));
    CHECK(!WCPLShouldCancel(30, 27));   // 30 < 27*1.15
    CHECK(!WCPLShouldCancel(20, 0));

    printf(fails ? "speed_math_test: %d failure(s)\n" : "speed_math_test: ok\n", fails);
    return fails != 0;
}
