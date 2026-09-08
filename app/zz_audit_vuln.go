package main

// AUDIT ARTIFACT — pulls a known-vulnerable golang.org/x/net into the compiled
// binary so Gate 3 can be shown blocking it. Deleted immediately after capture.
import _ "golang.org/x/net/http2"
