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

Your tests and local development need running instances of Kafka and Apicurio. The best way to manage this is with a Docker Compose file that Quarkus can automatically start and manage.

**`src/test/resources/docker-compose-test-services.yml`**
(This minimal file is all you need for the test environment)

TODO: go over how we need to expose the LOCALHOST and how the code uses that in tests, how a real running environment would use the other setup.  Also point out that this example is plaintext and how production should use TLS.  Also, we need to add the Kafka topic to the compose file.



```yaml
version: '3.8'

services:
  kafka-test:
    image: apache/kafka:4.1.0 # Or your preferred Kafka/Redpanda image
    hostname: kafka-test
    ports:
      - "9092:9092" # Port for the app inside Docker
      - "9093:9093" # Exposed host port for tests
    environment:
      # --- Configuration for single-node KRaft mode ---
      KAFKA_NODE_ID: 1
      KAFKA_LISTENER_SECURITY_PROTOCOL_MAP: CONTROLLER:PLAINTEXT,PLAINTEXT:PLAINTEXT,LOCALHOST:PLAINTEXT
      KAFKA_LISTENERS: PLAINTEXT://0.0.0.0:9092,CONTROLLER://0.0.0.0:9093,LOCALHOST://0.0.0.0:9094
      KAFKA_ADVERTISED_LISTENERS: PLAINTEXT://kafka-test:9092,LOCALHOST://localhost:9093
      KAFKA_CONTROLLER_QUORUM_VOTERS: 1@kafka-test:9093
      KAFKA_PROCESS_ROLES: broker,controller
      KAFKA_CONTROLLER_LISTENER_NAMES: CONTROLLER
      KAFKA_CLUSTER_ID: 'test-cluster-id'
      KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR: 1
    labels:
      # This label is a command to Quarkus:
      # "When this container (on internal port 9094) is ready,
      #  set the 'kafka.bootstrap.servers' property to the exposed host port."
      io.quarkus.devservices.compose.config_map.9094: kafka.bootstrap.servers

  apicurio-registry-test:
    image: apicurio/apicurio-registry:3.0.11
    ports:
      - "8081:8080" # Port 8081 is exposed to the host
    environment:
      QUARKUS_PROFILE: 'prod'
      APICURIO_STORAGE_KIND: 'mem' # Use in-memory storage for simple tests
    labels:
      # This label does the same for the Apicurio URL
      io.quarkus.devservices.compose.config_map.8080: mp.messaging.connector.smallrye-kafka.apicurio.registry.url

```

### **Part 2: `application.properties` Configuration**

This file connects your Quarkus application to the services in Docker Compose.
TODO go over the kafka peroperties here.  Discuss a bit about what every topic needs for a producer and a consumer in an apicurio specific setup.

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

TODO: add more reference links to the kafka docs.

Reference:
https://quarkus.io/guides/kafka

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
TODO: show the kafka specific dependences but go into how this project has a toml for this

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