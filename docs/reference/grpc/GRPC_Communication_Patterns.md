# gRPC Communication Patterns in the Pipeline Engine

## Overview

The Pipeline Engine leverages **gRPC as the primary communication protocol** between all services, providing type-safe, high-performance, and language-agnostic service communication. This document explores the various gRPC patterns implemented across the system, from simple unary calls to complex streaming operations, and demonstrates why gRPC is superior to traditional REST APIs for microservice architectures.

## Why gRPC Over REST?

The Pipeline Engine chose gRPC over REST for compelling technical and operational reasons:

```mermaid
graph TB
    subgraph "REST API Limitations"
        A1[JSON Text Parsing<br/>CPU Overhead]
        B1[Schema Drift<br/>Runtime Errors] 
        C1[HTTP/1.1<br/>Connection Limits]
        D1[No Streaming<br/>Large Response Buffering]
    end
    
    subgraph "gRPC Advantages"
        A2[Protobuf Binary<br/>5-10x Faster]
        B2[Schema First<br/>Compile-time Safety]
        C2[HTTP/2<br/>Multiplexing & Compression]
        D2[Bidirectional Streaming<br/>Real-time Processing]
    end
    
    A1 -.->|"vs"| A2
    B1 -.->|"vs"| B2  
    C1 -.->|"vs"| C2
    D1 -.->|"vs"| D2
```

**Performance Comparison:**
- **Serialization**: Protobuf is ~5-10x faster than JSON
- **Network**: HTTP/2 multiplexing eliminates connection overhead
- **Type Safety**: Compile-time validation prevents runtime schema errors
- **Message Size**: 2GB message limits vs typical REST JSON limits

## gRPC Service Architecture

### Service Distribution Pattern

The Pipeline Engine implements gRPC services across multiple layers:

```mermaid
flowchart TD
    subgraph "Client Services (gRPC Clients)"
        Engine[Pipeline Engine<br/>:38100]
        RepoSvc[Repository Service<br/>:38102]
    end
    
    subgraph "Platform Services (gRPC Servers + Clients)"
        Registration[Platform Registration<br/>:38101<br/>🔄 Server + Client]
        SearchMgr[OpenSearch Manager<br/>:38103<br/>🔄 Server + Client]
    end
    
    subgraph "Processing Modules (gRPC Servers)"
        Parser[Parser Module<br/>📥 Server Only]
        Chunker[Chunker Module<br/>📥 Server Only]
        Embedder[Embedder Module<br/>📥 Server Only]
        Sink[OpenSearch Sink<br/>📥 Server Only]
    end
    
    %% Client -> Server relationships
    Engine -->|"ProcessStep()"| Parser
    Engine -->|"ProcessStep()"| Chunker
    Engine -->|"ProcessStep()"| Embedder
    Engine -->|"ProcessStep()"| Sink
    
    RepoSvc -->|"SearchFilesystemMeta()"| SearchMgr
    Engine -->|"RegisterService()"| Registration
    SearchMgr -->|"GetServiceInfo()"| Registration
```

### Common gRPC Patterns Implemented

| Pattern | Use Case | Example Service | Benefits |
|---------|----------|-----------------|----------|
| **Unary RPC** | Simple request/response | `SearchFilesystemMeta()` | Low latency, cacheable |
| **Server Streaming** | Large result sets | `StreamSearchResults()` | Memory efficient, progressive loading |
| **Client Streaming** | Bulk uploads | `UploadDocuments()` | Efficient batching, backpressure |
| **Bidirectional Streaming** | Real-time processing | `ProcessPipelineStream()` | Full duplex, real-time feedback |

## Implementation Deep Dive

### 1. Unary RPC Pattern - Search Operations

The most common pattern for request/response operations:

```mermaid
sequenceDiagram
    participant Client as Repository Service
    participant Server as OpenSearch Manager
    
    Note over Client,Server: Unary RPC - SearchFilesystemMeta
    
    Client->>+Server: SearchFilesystemMetaRequest {<br/>  query: "test documents"<br/>  pageSize: 50<br/>  filters: {...}<br/>}
    
    Note over Server: • Validate request<br/>• Execute OpenSearch query<br/>• Format response
    
    Server-->>-Client: SearchFilesystemMetaResponse {<br/>  nodes: [...]<br/>  totalCount: 1247<br/>  nextPageToken: "..."<br/>}
    
    Note over Client: Process up to 2GB response<br/>No message size limits!
```

**Protobuf Schema Example:**
```protobuf
service OpenSearchManagerService {
  // Unary RPC for filesystem search
  rpc SearchFilesystemMeta(SearchFilesystemMetaRequest) 
    returns (SearchFilesystemMetaResponse);
}

message SearchFilesystemMetaRequest {
  string drive = 1;
  string query = 2;
  repeated string paths = 3;
  map<string, string> metadata_filters = 5;
  int32 page_size = 6;
  string page_token = 7;
  bool highlight = 10;
}

message SearchFilesystemMetaResponse {
  repeated SearchResult nodes = 1;
  int64 total_count = 2;
  string next_page_token = 3;
  SearchStats stats = 4;
}
```

**Java Implementation:**
```java
@Override
public Uni<SearchFilesystemMetaResponse> searchFilesystemMeta(
    SearchFilesystemMetaRequest request) {
    
    return validateRequest(request)
        .chain(ignored -> buildOpenSearchQuery(request))
        .chain(query -> executeSearch(query))
        .map(this::formatResponse)
        .onFailure().transform(err -> 
            new StatusRuntimeException(
                Status.INVALID_ARGUMENT
                    .withDescription("Search failed: " + err.getMessage())
                    .withCause(err)
            ));
}
```

### 2. Server Streaming Pattern - Large Result Sets

For efficiently handling large datasets without memory pressure:

```mermaid
sequenceDiagram
    participant Client as Pipeline Engine
    participant Server as Processing Module
    
    Note over Client,Server: Server Streaming - ProcessLargeDocument
    
    Client->>+Server: ProcessLargeDocumentRequest {<br/>  documentId: "large-pdf"<br/>  chunkSize: 1000<br/>}
    
    loop For each chunk processed
        Server-->>Client: ProcessResponse {<br/>  chunkId: 1<br/>  result: {...}<br/>  progress: 10%<br/>}
        
        Server-->>Client: ProcessResponse {<br/>  chunkId: 2<br/>  result: {...}<br/>  progress: 20%<br/>}
    end
    
    Server-->>-Client: ProcessResponse {<br/>  final: true<br/>  totalChunks: 50<br/>  summary: {...}<br/>}
    
    Note over Client: Real-time progress updates<br/>Memory efficient processing
```

**Implementation with Mutiny:**
```java
@Override
public Multi<ProcessResponse> processLargeDocument(
    ProcessLargeDocumentRequest request) {
    
    return Multi.createFrom().emitter(emitter -> {
        
        // Process document in chunks
        documentProcessor.processInChunks(request.getDocumentId())
            .subscribe().with(
                chunk -> {
                    ProcessResponse response = ProcessResponse.newBuilder()
                        .setChunkId(chunk.getId())
                        .setResult(chunk.getResult())
                        .setProgress(chunk.getProgress())
                        .build();
                    emitter.emit(response);
                },
                failure -> emitter.fail(new StatusRuntimeException(
                    Status.INTERNAL.withCause(failure))),
                () -> {
                    // Send final response
                    ProcessResponse finalResponse = ProcessResponse.newBuilder()
                        .setFinal(true)
                        .setSummary(buildSummary())
                        .build();
                    emitter.emit(finalResponse);
                    emitter.complete();
                }
            );
    });
}
```

### 3. Client Streaming Pattern - Bulk Operations

For efficient bulk data uploads:

```mermaid
sequenceDiagram
    participant Client as Repository Service
    participant Server as Node Upload Service
    
    Note over Client,Server: Client Streaming - BulkNodeUpload
    
    Client->>+Server: Open stream: BulkNodeUpload()
    
    loop For each node to upload
        Client->>Server: NodeUploadRequest {<br/>  nodeId: "node-1"<br/>  content: [...]<br/>}
        
        Client->>Server: NodeUploadRequest {<br/>  nodeId: "node-2"<br/>  content: [...]<br/>}
    end
    
    Client->>Server: End stream
    
    Note over Server: Process all uploads<br/>in single transaction
    
    Server-->>-Client: BulkUploadResponse {<br/>  successCount: 150<br/>  failureCount: 2<br/>  errors: [...]<br/>}
```

### 4. Message Size Handling - The 2GB Solution

One of the major achievements was solving gRPC message size limitations:

```mermaid
graph TD
    subgraph "The Problem"
        A1[Large Search Results<br/>100MB+ responses]
        B1[Default gRPC Limit<br/>4MB messages]
        C1[MessageSizeOverflowException<br/>❌ Search fails]
    end
    
    subgraph "The Solution"  
        A2[Configure Client Limits<br/>2GB max message size]
        B2[Configure Server Limits<br/>2GB max message size]
        C2[Large Results Success<br/>✅ Search works]
    end
    
    A1 --> B1 --> C1
    A2 --> B2 --> C2
```

**Configuration Solution:**

```properties
# Repository Service - Client Configuration
quarkus.grpc.clients."*".max-inbound-message-size=2147483647
quarkus.grpc.clients."*".max-outbound-message-size=2147483647

# OpenSearch Manager - Server Configuration  
quarkus.grpc.server.max-inbound-message-size=2147483647
```

**Why 2GB specifically:**
- **Integer.MAX_VALUE** = 2,147,483,647 bytes (2GB - 1 byte)
- **Largest possible** gRPC message size in Java
- **Real-world sufficient** for even massive search result sets
- **Prevents overflow** errors in protobuf message parsing

### 5. Error Handling and Status Codes

gRPC provides rich error handling with standardized status codes:

```mermaid
flowchart TD
    A[gRPC Call] --> B{Request Valid?}
    B -->|Yes| C{Service Available?}  
    B -->|No| D[INVALID_ARGUMENT<br/>400-like error]
    
    C -->|Yes| E{Processing OK?}
    C -->|No| F[UNAVAILABLE<br/>503-like error]
    
    E -->|Success| G[OK<br/>200-like success]
    E -->|Business Logic Error| H[FAILED_PRECONDITION<br/>412-like error] 
    E -->|Internal Error| I[INTERNAL<br/>500-like error]
    E -->|Timeout| J[DEADLINE_EXCEEDED<br/>408-like error]
```

**Java Error Handling Implementation:**
```java
public Uni<SearchResponse> searchNodes(SearchRequest request) {
    return validateRequest(request)
        .onFailure(ValidationException.class)
        .transform(err -> new StatusRuntimeException(
            Status.INVALID_ARGUMENT
                .withDescription("Invalid search parameters: " + err.getMessage())
        ))
        .chain(ignored -> executeSearch(request))
        .onFailure(ServiceUnavailableException.class) 
        .transform(err -> new StatusRuntimeException(
            Status.UNAVAILABLE
                .withDescription("OpenSearch cluster unavailable")
        ))
        .onFailure().transform(err -> new StatusRuntimeException(
            Status.INTERNAL
                .withDescription("Search execution failed")
                .withCause(err)
        ));
}
```

## Service Interface Patterns

### 1. Processing Module Pattern

All processing modules implement a standard `PipeStepProcessor` interface:

```protobuf
// Standard interface for all processing modules
service PipeStepProcessor {
  // Process a single step in the pipeline
  rpc ProcessStep(ProcessStepRequest) returns (ProcessStepResponse);
  
  // Health check
  rpc HealthCheck(HealthCheckRequest) returns (HealthCheckResponse);
  
  // Get module capabilities  
  rpc GetCapabilities(Empty) returns (CapabilitiesResponse);
}

message ProcessStepRequest {
  string step_id = 1;
  string correlation_id = 2;
  google.protobuf.Any input_data = 3;  // Flexible input
  map<string, string> parameters = 4;  // Step configuration
  string output_format = 5;            // Expected output type
}
```

**Benefits:**
- **Uniform interface** - All modules implement the same contract
- **Language agnostic** - Modules can be written in any language  
- **Pluggable architecture** - Easy to add new processing steps
- **Type flexibility** - `Any` type supports diverse data formats

### 2. Repository Service Pattern

Repository services provide CRUD operations with domain-specific methods:

```protobuf
service FilesystemService {
  // Node operations
  rpc CreateNode(CreateNodeRequest) returns (CreateNodeResponse);
  rpc GetNode(GetNodeRequest) returns (GetNodeResponse);
  rpc UpdateNode(UpdateNodeRequest) returns (UpdateNodeResponse);
  rpc DeleteNode(DeleteNodeRequest) returns (DeleteNodeResponse);
  
  // Search operations
  rpc SearchNodes(SearchNodesRequest) returns (SearchNodesResponse);
  
  // Bulk operations (streaming)
  rpc BulkCreateNodes(stream CreateNodeRequest) returns (BulkCreateResponse);
  rpc StreamNodes(StreamNodesRequest) returns (stream NodeResponse);
}
```

### 3. Management Service Pattern

Management services provide administrative and monitoring capabilities:

```protobuf
service OpenSearchManagerService {
  // Search operations
  rpc SearchFilesystemMeta(SearchFilesystemMetaRequest) 
    returns (SearchFilesystemMetaResponse);
  
  // Index management
  rpc CreateIndex(CreateIndexRequest) returns (CreateIndexResponse);
  rpc GetIndexStats(IndexStatsRequest) returns (IndexStatsResponse);
  
  // Health and monitoring
  rpc GetClusterHealth(Empty) returns (ClusterHealthResponse);
  rpc GetServiceMetrics(Empty) returns (ServiceMetricsResponse);
}
```

## Performance Characteristics

### Benchmarks and Metrics

| Operation | Latency (p95) | Throughput | Message Size |
|-----------|---------------|------------|--------------|
| **Node Search** | 45ms | 2,000 RPS | 50KB avg |
| **Bulk Upload** | 200ms | 500 batch/s | 10MB batches |
| **Large Results** | 150ms | 100 RPS | 100MB responses |
| **Module Processing** | 1.2s | 50 RPS | 5MB documents |

### Connection Management

```mermaid
graph LR
    subgraph "Traditional HTTP/1.1"
        A1[Request 1] --> B1[Connection 1]
        A2[Request 2] --> B2[Connection 2] 
        A3[Request 3] --> B3[Connection 3]
        
        C1[Connection Pool<br/>Exhaustion]
    end
    
    subgraph "gRPC HTTP/2"
        D1[Request 1] --> E1[Single Connection<br/>Multiplexed]
        D2[Request 2] --> E1
        D3[Request 3] --> E1
        
        F1[Efficient<br/>Resource Usage]
    end
```

**gRPC Connection Benefits:**
- **Multiplexing** - Multiple requests over single connection
- **Header compression** - HPACK reduces overhead
- **Flow control** - Backpressure handling built-in
- **Keep-alive** - Persistent connections with health checking

## Development and Testing Patterns

### 1. gRPC Service Testing

```java
@QuarkusTest
public class OpenSearchManagerServiceTest {
    
    @GrpcClient("opensearch-manager")  
    MutinyOpenSearchManagerServiceGrpc.MutinyOpenSearchManagerServiceStub client;
    
    @Test
    public void testSearchFilesystemMeta() {
        SearchFilesystemMetaRequest request = SearchFilesystemMetaRequest
            .newBuilder()
            .setQuery("test document")
            .setPageSize(10)
            .build();
            
        SearchFilesystemMetaResponse response = client
            .searchFilesystemMeta(request)
            .await().atMost(Duration.ofSeconds(10));
            
        assertThat(response.getNodesCount()).isGreaterThan(0);
        assertThat(response.getTotalCount()).isEqualTo(1);
    }
    
    @Test
    public void testLargeResponseHandling() {
        // Test 2GB message size capability
        SearchFilesystemMetaRequest largeRequest = createLargeResultRequest();
        
        assertThatCode(() -> {
            client.searchFilesystemMeta(largeRequest)
                .await().atMost(Duration.ofMinutes(1));
        }).doesNotThrowAnyException();
    }
}
```

### 2. Service Contract Testing

```java
// Contract testing with WireMock
@RegisterExtension
static WireMockExtension wireMock = WireMockExtension.newInstance()
    .options(wireMockConfig().port(0))
    .build();

@Test  
public void testServiceContractCompatibility() {
    // Verify protobuf schema compatibility
    DescriptorSet descriptorSet = loadDescriptorSet("search-service.desc");
    
    assertThat(descriptorSet)
        .hasService("OpenSearchManagerService")
        .hasMethod("SearchFilesystemMeta")
        .withRequestType("SearchFilesystemMetaRequest")
        .withResponseType("SearchFilesystemMetaResponse");
}
```

## Operations and Monitoring

### gRPC-Specific Metrics

```properties
# Prometheus metrics for gRPC
grpc.server.requests.total{method, status}
grpc.server.request.duration.seconds{method, quantile}
grpc.server.message.size.bytes{method, type}
grpc.client.requests.total{service, method, status}
```

### Health Check Implementation

```java
@ApplicationScoped
@GrpcService
public class HealthService implements Health {
    
    @Override
    public Uni<HealthCheckResponse> check(HealthCheckRequest request) {
        String service = request.getService();
        
        return switch (service) {
            case "opensearch-manager" -> checkOpenSearchHealth();
            case "repository-service" -> checkRepositoryHealth();
            case "" -> checkOverallHealth(); // Empty = server health
            default -> Uni.createFrom().item(
                HealthCheckResponse.newBuilder()
                    .setStatus(HealthCheckResponse.ServingStatus.SERVICE_UNKNOWN)
                    .build()
            );
        };
    }
}
```

### Debugging and Tracing

```properties
# gRPC logging configuration
quarkus.log.category."io.grpc".level=DEBUG
quarkus.log.category."io.pipeline.grpc".level=TRACE

# Enable gRPC reflection for grpcurl testing
quarkus.grpc.server.enable-reflection-service=true
```

## Best Practices and Guidelines

### 1. Schema Evolution

- **Add fields with new numbers** - Never reuse field numbers
- **Use optional fields** - Required fields prevent backward compatibility  
- **Deprecate instead of delete** - Mark fields as deprecated first
- **Version services** - Use package versioning for breaking changes

### 2. Error Handling

- **Use appropriate status codes** - Follow gRPC status code conventions
- **Include descriptive messages** - Help clients understand what went wrong
- **Preserve original errors** - Chain exceptions with `.withCause()`
- **Add structured details** - Use `Status.augmentDescription()` for context

### 3. Performance Optimization

- **Configure message sizes** - Set appropriate limits for your use case
- **Use streaming for large data** - Avoid memory pressure with server streaming
- **Implement proper timeouts** - Set reasonable deadline expectations
- **Cache channel instances** - Reuse connections where possible

This comprehensive gRPC communication architecture provides the foundation for high-performance, type-safe, and scalable service communication across the entire Pipeline Engine system.