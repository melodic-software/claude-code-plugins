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
