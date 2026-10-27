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
