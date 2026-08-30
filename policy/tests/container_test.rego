package main

import rego.v1

# ---- Core rule tests ----

test_compliant_image_allowed if {
	count(deny) == 0 with input as {"image": {
		"user": "65532",
		"digest": "sha256:aaa",
		"signed": true,
		"sbom_attested": true,
		"base_image": "gcr.io/distroless/static-debian12",
	}}
}

test_root_user_denied if {
	some msg in deny with input as {"image": {
		"user": "root",
		"digest": "sha256:aaa",
		"signed": true,
		"sbom_attested": true,
		"base_image": "gcr.io/distroless/static-debian12",
	}}
	contains(msg, "runs as root")
}

test_uid_zero_denied if {
	count(deny) > 0 with input as {"image": {
		"user": "0",
		"digest": "sha256:aaa",
		"signed": true,
		"sbom_attested": true,
		"base_image": "gcr.io/distroless/static-debian12",
	}}
}

test_bad_base_image_denied if {
	some msg in deny with input as {"image": {
		"user": "65532",
		"digest": "sha256:aaa",
		"signed": true,
		"sbom_attested": true,
		"base_image": "ubuntu:22.04",
	}}
	contains(msg, "not approved")
}

test_unsigned_denied if {
	some msg in deny with input as {"image": {
		"user": "65532",
		"digest": "sha256:aaa",
		"signed": false,
		"sbom_attested": true,
		"base_image": "gcr.io/distroless/static-debian12",
	}}
	contains(msg, "not signed")
}

test_missing_sbom_denied if {
	some msg in deny with input as {"image": {
		"user": "65532",
		"digest": "sha256:aaa",
		"signed": true,
		"sbom_attested": false,
		"base_image": "gcr.io/distroless/static-debian12",
	}}
	contains(msg, "SBOM attestation")
}

test_tag_reference_denied if {
	some msg in deny with input as {"image": {
		"user": "65532",
		"digest": "v1.0.0",
		"signed": true,
		"sbom_attested": true,
		"base_image": "gcr.io/distroless/static-debian12",
	}}
	contains(msg, "sha256 digest")
}

# ---- Field-presence (fail-closed) tests ----

test_missing_signed_key_denied if {
	some msg in deny with input as {"image": {
		"user": "65532",
		"digest": "sha256:aaa",
		"sbom_attested": true,
		"base_image": "gcr.io/distroless/static-debian12",
	}}
	contains(msg, "\"signed\" is missing")
}

test_missing_user_key_denied if {
	some msg in deny with input as {"image": {
		"digest": "sha256:aaa",
		"signed": true,
		"sbom_attested": true,
		"base_image": "gcr.io/distroless/static-debian12",
	}}
	contains(msg, "\"user\" is missing")
}

test_missing_digest_key_denied if {
	some msg in deny with input as {"image": {
		"user": "65532",
		"signed": true,
		"sbom_attested": true,
		"base_image": "gcr.io/distroless/static-debian12",
	}}
	contains(msg, "\"digest\" is missing")
}

test_missing_sbom_key_denied if {
	some msg in deny with input as {"image": {
		"user": "65532",
		"digest": "sha256:aaa",
		"signed": true,
		"base_image": "gcr.io/distroless/static-debian12",
	}}
	contains(msg, "\"sbom_attested\" is missing")
}
