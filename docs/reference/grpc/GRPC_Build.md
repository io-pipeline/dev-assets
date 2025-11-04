# gRPC Build: What Gets Built, How It’s Used, and Where It’s Consumed

This document explains the gRPC build in this repository: what lives under grpc/, how the Gradle build generates and packages stubs, how the backend consumes Mutiny stubs, how the frontend uses Connect-ES (TypeScript) codegen, how the descriptor set is produced and why it exists (WireMock), and common workflows and troubleshooting.

Related docs:
- docs/architecture/GRPC_Communication_Patterns.md – runtime patterns and why gRPC
- TYPESCRIPT_STUB_USAGE.md – hands-on TypeScript stub generation and usage


## Repository layout

- grpc/
  - grpc-stubs/ – Single source of truth for .proto files and the Java gRPC artifacts we publish internally. Its Gradle build:
    - Generates Quarkus/Mutiny Java stubs from proto
    - Produces a descriptor set (services.dsc) and embeds it into the jar under META-INF/grpc/
    - Publishes a Java library with API-pinned protobuf/grpc versions for consistent dependency alignment across the workspace

Other services/modules in applications/, libraries/, and modules/ consume the stubs as a normal Gradle/Maven dependency.


## Build mechanics (grpc/grpc-stubs)

File: grpc/grpc-stubs/build.gradle

Key points:
- Plugins: java-library, io.quarkus, org.kordamp.gradle.jandex, maven-publish
- Dependencies:
  - implementation io.quarkus:quarkus-grpc and quarkus-arc enable Quarkus’ gRPC code generation and DI
  - api com.google.protobuf:protobuf-java and io.grpc:grpc-{protobuf,stub} are pinned and re-exposed transitively so consumers don’t drift
- Java target: 21
- Quarkus codegen:
  - quarkus.generate-code.grpc.descriptor-set.generate=true
  - quarkus.generate-code.grpc.descriptor-set.name=services.dsc
  - This produces a descriptor set file during the build at build/classes/java/quarkus-generated-sources/grpc/services.dsc
- Packaging: The jar task adds services.dsc into META-INF/grpc/ so tooling (like WireMock or other reflection-based tools) can load descriptors directly from the classpath artifact
- Publishing: The module is publishable as a Maven publication (name: Pipeline gRPC Stubs)

What gets generated at build time:
- Backend Java stubs (including Mutiny reactive variants) for every service defined in src/main/proto/*.proto
- The descriptor set (services.dsc) covering all services/messages


## Backend consumption: Mutiny stubs (Quarkus)

All Quarkus-based backend services consume the grpc-stubs artifact. With the Quarkus gRPC extension enabled in the consuming service:
- Server side: Implement generated service interfaces (or extend generated base classes). Quarkus wires them as gRPC services.
- Client side: Inject Mutiny service clients (e.g., @GrpcClient) to call other services using reactive types (io.smallrye.mutiny.Uni/Multi).

Notes:
- The Mutiny stubs are generated automatically by Quarkus during the build based on the .proto files in grpc-stubs.
- Because grpc-stubs exports pinned versions of protobuf/grpc via api dependencies, consumers get a consistent, aligned version set.


## Frontend consumption: Connect-ES (TypeScript)

The frontend does not use the Java artifacts; instead it generates TypeScript clients using Buf’s protoc plugins:
- @bufbuild/protoc-gen-es for message types
- @connectrpc/protoc-gen-connect-es for Connect-compatible service clients

Where to find the step-by-step guide: see TYPESCRIPT_STUB_USAGE.md

Highlights:
- Transport: Frontend uses @connectrpc/connect-web with HTTP/1.1 and binary format, which is compatible with Envoy/NGINX/gRPC-web or Connect endpoints exposed by backend gateways.
- Client: createPromiseClient(Service, transport) from @connectrpc/connect
- Source of truth: Same .proto files from grpc-stubs/src/main/proto. Teams either:
  - run protoc locally pointing at those proto files, or
  - reuse a published proto package source if available (not yet configured in this repo) to decouple from the Java build.


## Descriptor set and WireMock

Why the descriptor set exists:
- Tools like WireMock can dynamically serve or proxy gRPC services using only the compiled descriptors (no source proto required).
- It also helps with integration testing and contract validation by providing a schema artifact that test harnesses can load.

Where it is packaged:
- Inside the grpc-stubs jar at META-INF/grpc/services.dsc

Typical usages:
- Local testing: A test harness can locate services.dsc on the classpath, load it, and configure stubs/mappings without hard-coding message schemas.
- Contract checks: CI jobs or test utilities can parse the descriptor to validate that breaking changes are not introduced (e.g., field re-numbering) before deployment.

Note: The repository includes reference code for WireMock under reference-code/, but the important integration point for our build is simply that the descriptors are present in the published jar for any consumer to load at runtime.


## Version alignment and dependency management

- grpc-stubs pins:
  - com.google.protobuf:protobuf-java:4.32.0
  - io.grpc:grpc-protobuf:1.75.0
  - io.grpc:grpc-stub:1.75.0
- These are exposed as api dependencies so downstream modules don’t accidentally pull divergent versions.
- The root Gradle platform/bom (see gradle/libs.versions.toml and the workspace’s platform) may also participate in alignment; grpc-stubs intentionally exports the chosen versions to avoid surprises in non-Quarkus consumers.


## Typical workflows

Backend developer workflow:
1) Edit proto files in grpc/grpc-stubs/src/main/proto/
2) Build grpc-stubs: ./gradlew :grpc:grpc-stubs:build
3) Use the updated generated Mutiny stubs in your Quarkus service (implement servers or inject clients)
4) If publishing for others: ./gradlew :grpc:grpc-stubs:publishToMavenLocal and update downstream builds to consume the new version

Frontend developer workflow:
1) Pull latest proto changes from grpc-stubs/src/main/proto
2) Regenerate TypeScript using the commands in TYPESCRIPT_STUB_USAGE.md
3) Update frontend code to use the generated *_connect.ts clients and *_pb.ts messages

Testing and WireMock:
- Integration tests and dev utilities may load META-INF/grpc/services.dsc from the grpc-stubs jar to dynamically construct servers/mappings without the original proto sources.


## CI/CD notes

- Building grpc-stubs is a standard Gradle build; no special steps beyond Quarkus codegen are required.
- If your pipeline publishes artifacts: ensure :grpc:grpc-stubs:publish is included to make the stubs available for downstream services and for frontend CI to pull proto sources (if you export them) or just to keep descriptor availability consistent.


## Troubleshooting

- “Class not found: generated gRPC class”
  - Ensure the consumer module depends on grpc-stubs and that Quarkus codegen has run (a full build usually fixes).
- “Missing descriptor set services.dsc in jar”
  - Verify the jar task in grpc-stubs/build.gradle is present and that quarkus.generate-code.grpc.descriptor-set.generate=true is set. Rebuild the module.
- Frontend: “Imports missing for *_connect or *_pb”
  - Re-run protoc generation as per TYPESCRIPT_STUB_USAGE.md, check tsconfig includes the generated folder, and validate paths.
- Version conflicts on protobuf/grpc
  - Because grpc-stubs exports api pins, a dependencyResolution warning indicates something else is enforcing different versions. Align via the root platform or exclude the conflicting transitive dep.


## FAQ

- Q: Why not store generated code in the repo?
  - A: We generate on build for the backend and generate within the frontend for TypeScript. Keeping sources of truth as .proto files avoids drift and merge conflicts.
- Q: Do we ship the proto files themselves as an artifact?
  - A: Not currently; the Java jar ships the compiled descriptor. Frontend uses the repo’s proto sources to generate. If needed, we can publish a proto-source artifact.
- Q: Is this gRPC or gRPC-Web on the frontend?
  - A: The frontend uses Connect-Web over HTTP/1.1 with binary framing via connect-es, compatible with gRPC-web deployments and edge proxies.
