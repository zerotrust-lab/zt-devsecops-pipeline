# METADATA
# title: Supply-chain attestation policy
# description: Requires a signed SBOM attestation to be present on the image.
package main

import rego.v1

# RULE 5a: the sbom_attested field must be present (fail closed if absent).
deny contains msg if {
	not "sbom_attested" in object.keys(input.image)
	msg := "POLICY VIOLATION: required image field \"sbom_attested\" is missing from policy input"
}

# RULE 5b: a signed SBOM (CycloneDX) attestation must exist.
deny contains msg if {
	input.image.sbom_attested != true
	msg := "SUPPLY-CHAIN VIOLATION: no signed SBOM attestation found; every image must ship a verifiable SBOM"
}

# Convenience boolean other tools can consume.
compliant if {
	count(deny) == 0
}
