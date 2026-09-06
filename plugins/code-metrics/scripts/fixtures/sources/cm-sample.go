// Package sample is a fixture source for the code-metrics suites: one
// function with two branches and a comment, so every collector has something
// to report. Formatted with gofmt (tabs).
package sample

// Classify returns a coarse label for value.
func Classify(value int) string {
	if value > 0 {
		return "positive"
	}
	if value == 0 {
		return "zero"
	}
	return "negative"
}
