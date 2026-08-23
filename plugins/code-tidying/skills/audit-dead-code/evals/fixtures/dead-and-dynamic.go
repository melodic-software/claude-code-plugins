// Package fixture is the capture input for the gopls (Go) lane.
//
// The lane's stated coverage limit is unexported symbols only: deadHandler is
// reported as a hint, ExportedEntry is not reported even though this package
// has no importer, and handleAlpha is reachable so it is not reported either.
package fixture

// ExportedEntry is exported, so gopls never hints it dead however unused it is.
func ExportedEntry(kind string) string {
	return handleAlpha(kind)
}

func handleAlpha(kind string) string {
	return "alpha:" + kind
}

func deadHandler(kind string) string {
	return "dead:" + kind
}
