#!/usr/bin/env bash
# A Gradle project with one class and one JUnit test.
set -euo pipefail
git init -q -b main
git config user.email eval@example.invalid
git config user.name eval
mkdir -p src/main/java/shop src/test/java/shop
cat >settings.gradle <<'G'
rootProject.name = 'shop'
G
cat >build.gradle <<'G'
plugins {
    id 'java'
}

repositories {
    mavenCentral()
}

dependencies {
    testImplementation 'org.junit.jupiter:junit-jupiter:5.11.3'
    testRuntimeOnly 'org.junit.platform:junit-platform-launcher'
}

test {
    useJUnitPlatform()
}
G
cat >src/main/java/shop/Discount.java <<'J'
package shop;

public final class Discount {
    private Discount() {
    }

    public static int apply(int price, int percent) {
        if (percent <= 0) {
            return price;
        }
        return price - price * percent / 100;
    }
}
J
cat >src/test/java/shop/DiscountTest.java <<'J'
package shop;

import static org.junit.jupiter.api.Assertions.assertEquals;

import org.junit.jupiter.api.Test;

class DiscountTest {
    @Test
    void appliesPercent() {
        assertEquals(90, Discount.apply(100, 10));
    }

    @Test
    void ignoresZeroPercent() {
        assertEquals(100, Discount.apply(100, 0));
    }
}
J
git add -A
git commit -q -m "feat: discount"
git update-ref refs/remotes/origin/main "$(git rev-parse HEAD)"
git symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
