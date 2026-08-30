# METADATA
# title: Container image compliance policy
# description: Zero-Trust rules -- required fields present, non-root, approved base, digest-pinned, signed.
package main

import rego.v1

approved_base_images := {
	"gcr.io/distroless/static-debian12",
	"gcr.io/distroless/base-debian12",
}

root_users := {"", "0", "root", "0:0"}

# Fields that MUST be present in the policy input. Absent fields are a
# fail-closed condition: in Rego, `undefined != true` is itself undefined, so a
# missing key would silently skip its deny rule and the image would pass.
required_fields := {"user", "digest", "signed", "base_image"}

# RULE 0: required fields must exist (defense in depth -- fail closed).
deny contains msg if {
	some f in required_fields
	not f in object.keys(input.image)
	msg := sprintf("POLICY VIOLATION: required image field %q is missing from policy input", [f])
}

# RULE 1: the image must NOT run as root.
deny contains msg if {
	user := input.image.user
	root_users[user]
	msg := sprintf("SECURITY VIOLATION: image runs as root (user=%q); must run as non-root UID such as 65532", [user])
}

# Defense in depth: a numeric UID of 0 is also root.
deny contains msg if {
	user := input.image.user
	to_number(user) == 0
	msg := "SECURITY VIOLATION: image user resolves to UID 0 (root)"
}

# RULE 2: the base image must be on the approved allowlist.
deny contains msg if {
	not approved_base_images[input.image.base_image]
	msg := sprintf("POLICY VIOLATION: base image %q is not approved; allowed: %v", [input.image.base_image, approved_base_images])
}

# RULE 3: the image must be referenced by an immutable digest, not a tag.
deny contains msg if {
	not startswith(input.image.digest, "sha256:")
	msg := sprintf("POLICY VIOLATION: image must be pinned by sha256 digest, got %q", [input.image.digest])
}

# RULE 4: the image must carry a valid Cosign signature.
deny contains msg if {
	input.image.signed != true
	msg := "SUPPLY-CHAIN VIOLATION: image is not signed with Cosign; unsigned artifacts are rejected"
}
