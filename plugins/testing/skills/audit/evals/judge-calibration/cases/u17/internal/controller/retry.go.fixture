package controller

import (
	"context"
	cryptorand "crypto/rand"
	"errors"
	"math"
	"math/big"
	"time"

	clockpkg "github.com/melodic-software/ci-runner/internal/clock"
	"github.com/melodic-software/ci-runner/internal/scaleset"
)

type BackoffPolicy struct {
	Initial     time.Duration
	Maximum     time.Duration
	Multiplier  float64
	JitterRatio float64
	MaxAttempts int
	Jitter      func(time.Duration, float64) time.Duration
}

func DefaultBackoffPolicy() BackoffPolicy {
	return BackoffPolicy{
		Initial:     time.Second,
		Maximum:     time.Minute,
		Multiplier:  2,
		JitterRatio: 0.2,
		MaxAttempts: 6,
		Jitter:      cryptoJitter,
	}
}

func (p BackoffPolicy) validate() error {
	if p.Initial <= 0 || p.Maximum < p.Initial || p.Multiplier < 1 || math.IsNaN(p.Multiplier) || math.IsInf(p.Multiplier, 0) || p.JitterRatio < 0 || p.JitterRatio > 1 || p.MaxAttempts <= 0 {
		return errors.New("invalid backoff policy")
	}
	return nil
}

func (p BackoffPolicy) delay(attempt int, err error) time.Duration {
	delay := float64(p.Initial)
	for i := 1; i < attempt; i++ {
		delay *= p.Multiplier
		if delay >= float64(p.Maximum) {
			delay = float64(p.Maximum)
			break
		}
	}
	base := time.Duration(delay)
	if base > p.Maximum {
		base = p.Maximum
	}
	if p.Jitter != nil && p.JitterRatio > 0 {
		base = p.Jitter(base, p.JitterRatio)
	}
	var scaleErr *scaleset.Error
	if errors.As(err, &scaleErr) && scaleErr.RetryAfterSeconds > 0 {
		retryAfter := p.Maximum
		if scaleErr.RetryAfterSeconds <= int(p.Maximum/time.Second) {
			retryAfter = time.Duration(scaleErr.RetryAfterSeconds) * time.Second
		}
		if retryAfter > base {
			base = retryAfter
		}
	}
	return base
}

func cryptoJitter(base time.Duration, ratio float64) time.Duration {
	// Draw uniformly from [-ratio,+ratio]. A crypto source avoids shared PRNG
	// state and correlated clients; failure safely falls back to no jitter.
	const buckets = int64(1_000_001)
	n, err := cryptorand.Int(cryptorand.Reader, big.NewInt(buckets))
	if err != nil {
		return base
	}
	unit := (float64(n.Int64()) / float64(buckets-1) * 2) - 1
	factor := 1 + unit*ratio
	result := time.Duration(float64(base) * factor)
	if result <= 0 {
		return time.Nanosecond
	}
	return result
}

// RetryValue executes operation once plus bounded retry attempts. It only
// retries errors selected by retryable and every wait is context-cancellable.
func RetryValue[T any](ctx context.Context, clock clockpkg.Clock, policy BackoffPolicy, retryable func(error) bool, operation func(context.Context) (T, error)) (T, error) {
	var zero T
	if err := policy.validate(); err != nil {
		return zero, err
	}
	for attempt := 1; attempt <= policy.MaxAttempts; attempt++ {
		if err := ctx.Err(); err != nil {
			return zero, err
		}
		value, err := operation(ctx)
		if err == nil {
			return value, nil
		}
		if attempt == policy.MaxAttempts || !retryable(err) {
			return zero, err
		}
		if err := clock.Sleep(ctx, policy.delay(attempt, err)); err != nil {
			return zero, err
		}
	}
	return zero, errors.New("retry loop exhausted unexpectedly")
}
