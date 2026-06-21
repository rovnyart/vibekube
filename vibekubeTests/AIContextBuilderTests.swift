import Testing
@testable import vibekube

struct AIContextBuilderTests {
    @Test func redactsSecretManifestDataBlocks() {
        let yaml = """
        apiVersion: v1
        kind: Secret
        metadata:
          name: demo-secret
        data:
          password: cGFzc3dvcmQ=
          token: dG9rZW4=
        stringData:
          apiKey: raw-api-key
        type: Opaque
        """

        let redacted = AIContextRedactor.redactedManifest(yaml, kind: "Secret")

        #expect(redacted.contains("data:"))
        #expect(redacted.contains("password: <redacted>"))
        #expect(redacted.contains("token: <redacted>"))
        #expect(redacted.contains("apiKey: <redacted>"))
        #expect(redacted.contains("type: Opaque"))
        #expect(!redacted.contains("cGFzc3dvcmQ="))
        #expect(!redacted.contains("dG9rZW4="))
        #expect(!redacted.contains("raw-api-key"))
    }

    @Test func redactsCredentialTextInNonSecretManifest() {
        let yaml = """
        apiVersion: v1
        kind: ConfigMap
        data:
          config: Authorization: Bearer super-secret-token
          password: hunter2
        """

        let redacted = AIContextRedactor.redactedManifest(yaml, kind: "ConfigMap")

        #expect(redacted.contains("Bearer <redacted>"))
        #expect(redacted.contains("password: <redacted>"))
        #expect(!redacted.contains("super-secret-token"))
        #expect(!redacted.contains("hunter2"))
    }
}
