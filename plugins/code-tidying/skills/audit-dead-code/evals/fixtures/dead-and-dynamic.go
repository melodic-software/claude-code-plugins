package fixture

func ExportedEntry(kind string) string {
	return handleAlpha(kind)
}

func handleAlpha(kind string) string {
	return "alpha:" + kind
}

func deadHandler(kind string) string {
	return "dead:" + kind
}
