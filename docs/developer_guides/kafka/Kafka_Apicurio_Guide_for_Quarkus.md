# **Kafka Apicurio Guide for Quarkus**

## Introduction

### **Why Apicurio?**

The Apicurio Schema Registry is a powerful, open-source schema registry that can be used with Kafka, Kafka Streams, and other messaging systems.

It's a great fit for Kafka because it can be used to manage schemas for both Protobuf and Avro messages.

TODO: discuss schema evolution and how it works with Apicurio.  Go over the concept of schema management... 

### **Why this is great for test pipeline processing**

Messages change over time.  Often times previous messages that are in archives need to be processed again.  This is especially true for data that is being ingested from other systems.  Apicurio allows you to manage the schemas for these messages.  If a message is updated, the schema is updated automatically.  This allows you to test your pipeline with the latest schema.  However, if an older message is processed, it will still use the old schema.  This is a problem because the schema may have changed.  This is why we need to test the pipeline with the latest schema.

But should there be an incompatibility, we would have a record of that schema change.  This allows us to fix the schema and reprocess the data.

This extra upfront work prevents serialization issues that would otherwise occur from manual updates or incompatible schema changes.

## Getting Started

### **A Complete Guide: Robust Kafka & Apicurio in Quarkus**

The combination of Quarkus, Kafka, and Apicurio is powerful, but testing it can be difficult. The "magic" of dependency injection can fail in complex projects (as we saw).

This guide provides a "no-magic" approach that is reliable, debuggable, and works consistently.

### **Part 1: The Foundation - Docker Compose for Dev Services**

Your tests and local development need running instances of Kafka, Apicurio, and MySQL. The best way to manage this is with a Docker Compose file that Quarkus can automatically start and manage.

#### **Understanding the Listener Configuration**

Kafka requires multiple listeners when running in Docker:
- **PLAINTEXT** (`kafka-test:9092`): Internal listener for container-to-container communication (e.g., Apicurio connecting to Kafka)
- **LOCALHOST** (`localhost:9093`): External listener for your test code running on the host machine
- **CONTROLLER** (`kafka-test:9094`): KRaft controller listener for internal cluster management

Your tests use the LOCALHOST listener, while Apicurio uses the PLAINTEXT listener. This dual-listener setup is critical for Docker networking.

#### **Production vs Test Environments**

- **Test Environment** (shown below): Uses plaintext connections, in-memory storage for Apicurio, and exposed ports for direct access from test code
- **Production Environment**: Should use TLS encryption, persistent storage for Apicurio (SQL database), authentication, and internal networking without exposed ports

**`src/test/resources/compose-test-services.yml`**
(Complete test environment with Kafka, Apicurio, and MySQL)



```yaml
version: '3.8'

networks:
  pipeline-test-network:
    driver: bridge

services:
  # MySQL - Required for Apicurio SQL storage and application tests
  mysql-test:
    container_name: pipeline-mysql-test
    image: mysql:8.0
    networks:
      - pipeline-test-network
    ports:
      - "3307:3306"  # Exposed to host on 3307 to avoid conflicts with local MySQL
    environment:
      MYSQL_ROOT_PASSWORD: rootpassword
      MYSQL_DATABASE: apicurio_registry
      MYSQL_USER: pipeline
      MYSQL_PASSWORD: password
    healthcheck:
      test: ["CMD", "mysqladmin", "ping", "-h", "localhost", "-u", "root", "-prootpassword"]
      interval: 5s
      timeout: 5s
      retries: 10
    command: --default-authentication-plugin=mysql_native_password

  # Initialize databases (runs after MySQL is healthy)
  init-db:
    image: mysql:8.0
    networks:
      - pipeline-test-network
    depends_on:
      mysql-test:
        condition: service_healthy
    command: >
      bash -c "
      until mysql -h mysql-test -u root -prootpassword -e 'SELECT 1' >/dev/null 2>&1; do
        echo 'Waiting for MySQL...';
        sleep 1;
      done;
      mysql -h mysql-test -u root -prootpassword -e \"
      CREATE DATABASE IF NOT EXISTS apicurio_registry;
      CREATE DATABASE IF NOT EXISTS pipeline_connector_test;
      GRANT ALL PRIVILEGES ON apicurio_registry.* TO 'pipeline'@'%';
      GRANT ALL PRIVILEGES ON pipeline_connector_test.* TO 'pipeline'@'%';
      FLUSH PRIVILEGES;
      \"
      "

  # Kafka - KRaft mode (no Zookeeper needed)
  kafka-test:
    container_name: pipeline-kafka-test
    image: confluentinc/cp-kafka:7.7.1
    hostname: kafka-test
    networks:
      - pipeline-test-network
    ports:
      - "9092:9092"  # Internal listener (for Apicurio)
      - "9093:9093"  # External listener (for host/tests)
    environment:
      KAFKA_NODE_ID: 1
      KAFKA_LISTENER_SECURITY_PROTOCOL_MAP: CONTROLLER:PLAINTEXT,PLAINTEXT:PLAINTEXT,LOCALHOST:PLAINTEXT
      KAFKA_LISTENERS: PLAINTEXT://0.0.0.0:9092,CONTROLLER://0.0.0.0:9094,LOCALHOST://0.0.0.0:9093
      KAFKA_ADVERTISED_LISTENERS: PLAINTEXT://kafka-test:9092,LOCALHOST://localhost:9093
      KAFKA_CONTROLLER_QUORUM_VOTERS: 1@kafka-test:9094
      KAFKA_PROCESS_ROLES: broker,controller
      KAFKA_CONTROLLER_LISTENER_NAMES: CONTROLLER
      CLUSTER_ID: 'pipeline-test-cluster'
      KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR: 1
      KAFKA_TRANSACTION_STATE_LOG_REPLICATION_FACTOR: 1
      KAFKA_TRANSACTION_STATE_LOG_MIN_ISR: 1
    healthcheck:
      test: kafka-broker-api-versions --bootstrap-server localhost:9092
      interval: 5s
      timeout: 10s
      retries: 10

  # Apicurio Schema Registry - SQL storage with MySQL
  apicurio-registry-test:
    container_name: pipeline-apicurio-test
    image: apicurio/apicurio-registry:3.0.11
    networks:
      - pipeline-test-network
    ports:
      - "8081:8080"  # Apicurio API exposed on host port 8081
    environment:
      QUARKUS_PROFILE: 'prod'
      # SQL storage configuration
      APICURIO_STORAGE_KIND: 'sql'
      APICURIO_STORAGE_SQL_KIND: 'mysql'
      APICURIO_DATASOURCE_URL: 'jdbc:mysql://mysql-test:3306/apicurio_registry'
      APICURIO_DATASOURCE_USERNAME: 'pipeline'
      APICURIO_DATASOURCE_PASSWORD: 'password'
      # Kafka configuration for Apicurio to use PLAINTEXT listener
      KAFKA_BOOTSTRAP_SERVERS: 'kafka-test:9092'
    depends_on:
      mysql-test:
        condition: service_healthy
      kafka-test:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/health/ready"]
      interval: 5s
      timeout: 5s
      retries: 20

```

#### **Key Integration Points**

1. **MySQL Integration**:
   - Apicurio uses MySQL for persistent schema storage
   - `init-db` service creates required databases: `apicurio_registry` and `pipeline_connector_test`
   - Health checks ensure MySQL is ready before Apicurio starts

2. **Network Configuration**:
   - All services share the `pipeline-test-network` bridge network
   - Services reference each other by container name (e.g., `kafka-test`, `mysql-test`)

3. **Kafka Listener Strategy**:
   - `PLAINTEXT://kafka-test:9092` - Used by Apicurio (container-to-container)
   - `LOCALHOST://localhost:9093` - Used by host test code
   - `CONTROLLER://kafka-test:9094` - KRaft internal

4. **Health Checks**:
   - Ensures services start in correct order
   - Prevents Apicurio from starting before MySQL/Kafka are ready
   - Tests can rely on `service_healthy` conditions

5. **Port Mapping**:
   - MySQL: `3307:3306` (avoids conflict with local MySQL on 3306)
   - Kafka: `9093:9093` (external access for tests)
   - Apicurio: `8081:8080` (API access from tests)

### **Part 2: `application.properties` Configuration**

This file connects your Quarkus application to the services in Docker Compose.

#### **Understanding Kafka Properties for Apicurio**

Every Kafka producer and consumer in an Apicurio setup needs specific configuration:

**Producer Requirements**:
- `connector`: Set to `smallrye-kafka`
- `topic`: The Kafka topic name
- `key.serializer`: Usually `StringSerializer`
- `value.serializer`: `io.apicurio.registry.serde.protobuf.ProtobufKafkaSerializer` for Protobuf messages
- `apicurio.registry.auto-register`: Set to `true` to automatically register schemas
- `apicurio.registry.artifact-id`: Unique identifier for the schema in Apicurio
- `apicurio.registry.proto.message-name`: The Protobuf message class name

**Consumer Requirements**:
- `connector`: Set to `smallrye-kafka`
- `topic`: The Kafka topic name to subscribe to
- `value.deserializer`: `io.apicurio.registry.serde.protobuf.ProtobufKafkaDeserializer` for Protobuf messages
- `apicurio.registry.deserializer.value.return-class`: **CRITICAL** - The fully qualified Java class name to deserialize to (prevents `DynamicMessage` issues)

**Why `return-class` is Critical**:
Without specifying `return-class`, the Protobuf deserializer creates a `DynamicMessage` instead of your concrete Java class, causing `ClassCastException` errors. This property tells the deserializer exactly which class to instantiate.

```properties
# ======================================================
# 1. TEST PROFILE CONFIGURATION
# ======================================================
# Tell Quarkus to use your Docker Compose file for tests
%test.quarkus.devservices.enabled=true
%test.quarkus.compose.devservices.files=src/test/resources/docker-compose-test-services.yml
%test.quarkus.compose.devservices.start-services=true

# These will be OVERRIDDEN by the labels in the compose file
%test.kafka.bootstrap.servers=localhost:9093
%test.mp.messaging.connector.smallrye-kafka.apicurio.registry.url=http://localhost:8081/apis/registry/v3


# ======================================================
# 2. PRODUCER (SENDER) CONFIGURATION
# ======================================================
# --- For an outgoing channel named "account-events" ---
mp.messaging.outgoing.account-events.connector=smallrye-kafka
mp.messaging.outgoing.account-events.topic=account-events
mp.messaging.outgoing.account-events.key.serializer=org.apache.kafka.common.serialization.StringSerializer
mp.messaging.outgoing.account-events.value.serializer=io.apicurio.registry.serde.protobuf.ProtobufKafkaSerializer

# --- Apicurio config for the PRODUCER ---
mp.messaging.outgoing.account-events.apicurio.registry.auto-register=true
mp.messaging.outgoing.account-events.apicurio.registry.artifact-id=account-events-value
mp.messaging.outgoing.account-events.apicurio.registry.proto.message-name=AccountEvent


# ======================================================
# 3. CONSUMER (RECEIVER) CONFIGURATION
# ======================================================
# --- For an incoming channel named "drive-updates-in" ---
mp.messaging.incoming.drive-updates-in.connector=smallrye-kafka
mp.messaging.incoming.drive-updates-in.topic=drive-updates
mp.messaging.incoming.drive-updates-in.value.deserializer=io.apicurio.registry.serde.protobuf.ProtobufKafkaDeserializer

# --- Apicurio config for the CONSUMER ---
# CRITICAL: This is the property that tells the deserializer which Java class to create.
# This prevents the "DynamicMessage" ClassCastException.
mp.messaging.incoming.drive-updates-in.apicurio.registry.deserializer.value.return-class=io.pipeline.repository.filesystem.DriveUpdateNotification
```

### **Part 3: Application Code - The Producer (Sender)**

This is your application code that sends a message. It's clean and simple.

```java
import io.pipeline.repository.account.AccountEvent;
import jakarta.enterprise.context.ApplicationScoped;
import org.eclipse.microprofile.reactive.messaging.Channel;
import org.eclipse.microprofile.reactive.messaging.Emitter;

@ApplicationScoped
public class AccountEventPublisher {

    @Channel("account-events")
    Emitter<AccountEvent> emitter;

    public void publishAccountCreatedEvent(AccountEvent event) {
        // The channel name "account-events" links this emitter
        // to the properties in application.properties.
        emitter.send(event)
            .whenComplete((success, failure) -> {
                if (failure != null) {
                    LOG.errorf(failure, "Failed to send message: %s", failure.getMessage());
                } else {
                    LOG.infof("Message sent successfully!");
                }
            });
    }
}
```

-----

## Alternative Approach: Using Testcontainers

While Docker Compose works well for test environments, some services use Testcontainers for programmatic container management. This approach provides more control and better integration with JUnit lifecycle.

### **Testcontainers Implementation**

**Example from opensearch-manager (`OpenSearchTestResource.java`):**

```java
package io.pipeline.schemamanager;

import io.quarkus.test.common.QuarkusTestResourceLifecycleManager;
import org.jboss.logging.Logger;
import org.opensearch.testcontainers.OpenSearchContainer;
import org.testcontainers.containers.KafkaContainer;
import org.testcontainers.utility.DockerImageName;

import java.util.HashMap;
import java.util.Map;

public class OpenSearchTestResource implements QuarkusTestResourceLifecycleManager {

    private static final Logger LOG = Logger.getLogger(OpenSearchTestResource.class);

    private OpenSearchContainer<?> opensearch;
    private KafkaContainer kafka;

    @Override
    public Map<String, String> start() {
        Map<String, String> config = new HashMap<>();

        // Start Kafka container
        LOG.info("Starting Kafka test container...");
        kafka = new KafkaContainer(DockerImageName.parse("confluentinc/cp-kafka:7.7.1"))
                .withReuse(true);  // Reuse container across test runs for speed
        kafka.start();
        String kafkaBootstrapServers = kafka.getBootstrapServers();
        LOG.info("Kafka test container started at: " + kafkaBootstrapServers);

        // Start OpenSearch container
        LOG.info("Starting OpenSearch test container...");
        opensearch = new OpenSearchContainer<>(DockerImageName.parse("opensearchproject/opensearch:3.3.2"))
                .withAccessToHost(true)
                .withReuse(true);
        opensearch.start();
        LOG.info("OpenSearch test container started at: " + opensearch.getHost() + ":" + opensearch.getFirstMappedPort());

        String opensearchAddress = "http://" + opensearch.getHost() + ":" + opensearch.getFirstMappedPort();

        // Configure both services for Quarkus
        config.put("opensearch.hosts", opensearchAddress);
        config.put("kafka.bootstrap.servers", kafkaBootstrapServers);
        config.put("mp.messaging.connector.smallrye-kafka.bootstrap.servers", kafkaBootstrapServers);

        return config;
    }

    @Override
    public void stop() {
        if (opensearch != null) {
            LOG.info("Stopping OpenSearch test container...");
            opensearch.stop();
            LOG.info("OpenSearch test container stopped.");
        }
        if (kafka != null) {
            LOG.info("Stopping Kafka test container...");
            kafka.stop();
            LOG.info("Kafka test container stopped.");
        }
    }
}
```

### **Using the Test Resource**

In your test class, register the resource:

```java
@QuarkusTest
@QuarkusTestResource(OpenSearchTestResource.class)
public class YourServiceTest {
    // Tests automatically use the containers
}
```

### **Testcontainers vs Docker Compose**

**Testcontainers Advantages:**
- Programmatic control over container lifecycle
- Better integration with JUnit test lifecycle
- Can reuse containers across test runs (faster)
- Easier to customize per-test
- Dynamic port allocation

**Docker Compose Advantages:**
- Simpler setup for multiple interdependent services
- Easier to visualize full infrastructure
- Better for services with complex dependencies (MySQL + Kafka + Apicurio)
- Can be used for local development (not just tests)

**When to Use Each:**
- **Testcontainers**: Single or independent services (OpenSearch, single Kafka instance)
- **Docker Compose**: Complex multi-service setups (Kafka + Apicurio + MySQL + init scripts)

-----

## References and Further Reading

- [Quarkus Kafka Guide](https://quarkus.io/guides/kafka)
- [Apicurio Registry Documentation](https://www.apicur.io/registry/docs/)
- [SmallRye Reactive Messaging](https://smallrye.io/smallrye-reactive-messaging/)
- [Kafka KRaft Mode](https://kafka.apache.org/documentation/#kraft)
- [Testcontainers](https://www.testcontainers.org/)
- [Quarkus Dev Services](https://quarkus.io/guides/dev-services)

### **Part 4: Application Code - The Consumer (Receiver)**

This is an application that listens for messages (like your `opensearch-manager`).

```java
import io.pipeline.repository.filesystem.DriveUpdateNotification;
import io.smallrye.mutiny.Uni;
import jakarta.enterprise.context.ApplicationScoped;
import org.eclipse.microprofile.reactive.messaging.Incoming;
import org.eclipse.microprofile.reactive.messaging.Message;

@ApplicationScoped
public class DriveUpdateConsumer {

    @Incoming("drive-updates-in")
    public Uni<Void> consume(Message<DriveUpdateNotification> message) {
        DriveUpdateNotification notification = message.getPayload();
        
        // 1. Do your business logic (e.g., index to OpenSearch)
        LOG.infof("Indexing drive: %s", notification.getDrive().getName());
        
        // 2. Return a Uni that completes when you're done
        // 3. Acknowledge the message to commit the offset in Kafka
        return Uni.createFrom().voidItem()
            .onItem().transformToUni(v -> Uni.createFrom().completionStage(message.ack()));
    }
}
```

-----

### **Part 5: How to Test a PRODUCER (The "Account Service" Test)**

This is the pattern we built. It verifies your service sent the correct message to Kafka.

#### Testing components used in this test

* Kafka
* Apicurio
* gRPC
* Quarkus
* Awaitility
* JUnit 5
* MicroProfile Config
* MicroProfile Reactive Messaging
* Quarkus Test
* Quarkus gRPC Client
* Quarkus Kafka

**Note:** This test uses the gRPC client to call the gRPC service. This is a common pattern in Quarkus.  The gRPC client is a separate service that is injected into your test.  This tutorial is focused on Kafka but it slso demonstrates how gRPC's protobuf replies can work well with Apicurio and Kafka. 

**Dependencies (build.gradle):**

The Pipeline project uses a centralized BOM (Bill of Materials) for dependency management. Key Kafka/Apicurio dependencies are managed through the BOM catalog:

```groovy
dependencies {
    // Platform BOM provides version management
    implementation platform('io.pipeline:pipeline-bom:1.0.0-SNAPSHOT')

    // Quarkus Kafka support
    implementation 'io.quarkus:quarkus-grpc'
    implementation 'io.quarkus:quarkus-arc'

    // Kafka messaging (versions managed by BOM)
    // These are automatically included via pipeline-bom, but shown here for reference:
    // - org.apache.kafka:kafka-clients
    // - io.apicurio:apicurio-registry-serdes-protobuf-serde
    // - io.smallrye.reactive:smallrye-reactive-messaging-kafka

    // Test dependencies
    testImplementation 'io.quarkus:quarkus-junit5'
    testImplementation 'org.awaitility:awaitility'  // For async test assertions
}
```

The BOM catalog (`pipeline-bom-catalog`) centralizes versions for:
- Kafka clients (Confluent distribution)
- Apicurio serializers/deserializers
- SmallRye Reactive Messaging
- Protobuf dependencies

This ensures consistent versions across all Pipeline services and simplifies dependency management.

**Test Class (`AccountEventPublisherTest.java`):**

```java
import io.pipeline.repository.account.AccountEvent;
import io.pipeline.repository.account.AccountServiceGrpc;
import io.pipeline.repository.account.CreateAccountRequest;
import org.apache.kafka.clients.consumer.ConsumerConfig;
import org.apache.kafka.clients.consumer.ConsumerRecord;
import org.apache.kafka.clients.consumer.ConsumerRecords;
import org.apache.kafka.clients.consumer.KafkaConsumer;
import org.apache.kafka.common.serialization.StringDeserializer;
import io.apicurio.registry.serde.protobuf.ProtobufKafkaDeserializer;
import io.quarkus.grpc.GrpcClient;
import io.quarkus.test.junit.QuarkusTest;
import org.eclipse.microprofile.config.inject.ConfigProperty;
import org.junit.jupiter.api.Test;
import org.awaitility.Awaitility;
import org.hamcrest.Matchers;
import java.time.Duration;
import java.util.Collections;
import java.util.Properties;
import java.util.concurrent.TimeUnit;
import static org.junit.jupiter.api.Assertions.*;

@QuarkusTest
public class AccountEventPublisherTest {

    @GrpcClient("account-manager")
    AccountServiceGrpc.AccountServiceBlockingStub accountService; // Your gRPC service

    @ConfigProperty(name = "kafka.bootstrap.servers")
    String bootstrapServers;

    @ConfigProperty(name = "mp.messaging.outgoing.account-events.apicurio.registry.url")
    String apicurioRegistryUrl;

    /**
     * Creates a manual consumer configured to read Protobuf messages
     * using the Apicurio deserializer.
     */
    private KafkaConsumer<String, AccountEvent> createConsumer() {
        Properties props = new Properties();
        props.put(ConsumerConfig.BOOTSTRAP_SERVERS_CONFIG, bootstrapServers);
        props.put(ConsumerConfig.GROUP_ID_CONFIG, "test-group-" + System.currentTimeMillis());
        props.put(ConsumerConfig.KEY_DESERIALIZER_CLASS_CONFIG, StringDeserializer.class.getName());
        props.put(ConsumerConfig.VALUE_DESERIALIZER_CLASS_CONFIG, ProtobufKafkaDeserializer.class.getName());
        props.put(ConsumerConfig.AUTO_OFFSET_RESET_CONFIG, "earliest");
        
        // --- CRITICAL APICURIO CONFIG ---
        props.put("apicurio.registry.url", apicurioRegistryUrl);
        // This is the property that works, as found in your consumer app
        props.put("apicurio.registry.deserializer.value.return-class", AccountEvent.class.getName());
        
        return new KafkaConsumer<>(props);
    }

    @Test
    public void testAccountCreatedEventIsPublished() {
        String testAccountId = "test-kafka-create-" + System.currentTimeMillis();

        try (KafkaConsumer<String, AccountEvent> consumer = createConsumer()) {
            consumer.subscribe(Collections.singletonList("account-events"));

            // ACT: Call the service method that triggers the producer
            accountService.createAccount(CreateAccountRequest.newBuilder()
                    .setAccountId(testAccountId)
                    .setName("Kafka Test Account")
                    .build());

            // ASSERT: Use Awaitility to poll until we find our specific message
            AccountEvent foundEvent = Awaitility.await()
                .atMost(10, TimeUnit.SECONDS)
                .pollInterval(100, TimeUnit.MILLISECONDS)
                .until(() -> pollForMessage(consumer, testAccountId), Matchers.notNullValue());

            assertNotNull(foundEvent);
            assertTrue(foundEvent.hasCreated());
            assertEquals(testAccountId, foundEvent.getAccountId());
        }
    }

    // Helper method to poll for a message with a specific ID, avoiding "dirty topic" issues
    private AccountEvent pollForMessage(KafkaConsumer<String, AccountEvent> consumer, String accountId) {
        ConsumerRecords<String, AccountEvent> records = consumer.poll(Duration.ofMillis(100));
        for (ConsumerRecord<String, AccountEvent> record : records) {
            if (record.value().getAccountId().equals(accountId)) {
                return record.value(); // Found it!
            }
        }
        return null; // Didn't find it
    }
}
```

-----

### **Part 6: How to Test a CONSUMER (The "OpenSearch Manager" Test)**

This tests your service's ability to receive and process a message.

**Dependencies (build.gradle):**

```groovy
testImplementation 'io.quarkus:quarkus-junit5'
testImplementation 'io.quarkus:quarkus-junit5-mockito' // For @InjectMock
testImplementation 'org.awaitility:awaitility:4.2.0'
testImplementation 'org.apache.kafka:kafka-clients:3.4.0'
```

**Test Class (`DriveUpdateConsumerTest.java`):**

```java
import io.pipeline.repository.filesystem.Drive;
import io.pipeline.repository.filesystem.DriveUpdateNotification;
import io.pipeline.schemamanager.opensearch.OpenSearchIndexingService;
import io.quarkus.test.junit.QuarkusTest;
import io.quarkus.test.junit.mockito.InjectMock;
import org.apache.kafka.clients.producer.KafkaProducer;
import org.apache.kafka.clients.producer.ProducerConfig;
import org.apache.kafka.clients.producer.ProducerRecord;
import org.apache.kafka.common.serialization.StringSerializer;
import io.apicurio.registry.serde.protobuf.ProtobufKafkaSerializer;
import io.smallrye.mutiny.Uni;
import org.eclipse.microprofile.config.inject.ConfigProperty;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.Mockito;
import org.awaitility.Awaitility;
import java.util.Properties;
import java.util.concurrent.TimeUnit;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@QuarkusTest
public class DriveUpdateConsumerTest {

    // 1. Mock the downstream service your consumer calls
    @InjectMock
    OpenSearchIndexingService indexingService;

    // Inject config to build our test producer
    @ConfigProperty(name = "kafka.bootstrap.servers")
    String bootstrapServers;
    @ConfigProperty(name = "mp.messaging.connector.smallrye-kafka.apicurio.registry.url")
    String apicurioRegistryUrl;

    @BeforeEach
    public void setup() {
        Mockito.reset(indexingService);
    }

    // Helper to create a manual producer configured to send Protobuf
    private KafkaProducer<String, Object> createProducer() {
        Properties props = new Properties();
        props.put(ProducerConfig.BOOTSTRAP_SERVERS_CONFIG, bootstrapServers);
        props.put(ProducerConfig.KEY_SERIALIZER_CLASS_CONFIG, StringSerializer.class.getName());
        props.put(ProducerConfig.VALUE_SERIALIZER_CLASS_CONFIG, ProtobufKafkaSerializer.class.getName());
        props.put("apicurio.registry.url", apicurioRegistryUrl);
        props.put("apicurio.registry.auto-register", "true");
        return new KafkaProducer<>(props);
    }

    @Test
    public void testConsumer_onCreated_indexesDrive() {
        // ARRANGE: Mock the indexing service's behavior
        Drive drive = Drive.newBuilder().setName("test-drive-1").build();
        when(indexingService.indexDrive(any(Drive.class))).thenReturn(Uni.createFrom().voidItem());
        
        DriveUpdateNotification notification = DriveUpdateNotification.newBuilder()
                .setDrive(drive)
                .setUpdateType("CREATED")
                .build();
        
        // ACT: Send the message to the topic your consumer is listening to
        try (KafkaProducer<String, Object> producer = createProducer()) {
            producer.send(new ProducerRecord<>("drive-updates-in", drive.getName(), notification));
        }

        // ASSERT: Use Awaitility to wait until the mock is called
        Awaitility.await().atMost(5, TimeUnit.SECONDS).untilAsserted(() -> {
            // Verify your consumer called the correct method on the mock service
            verify(indexingService, Mockito.times(1)).indexDrive(drive);
        });
    }
}
```