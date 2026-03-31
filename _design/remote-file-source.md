# Remote File Source Design

## Overview

The Remote File Source feature enables Deephaven clients (e.g., web browsers) to provide source files (Groovy scripts) to the server for dynamic execution. This allows users to write and execute code from their local environment without manually uploading files to the server.

**Branch:** DH-20578_groovy-remote-file-sourcing

**Key Capabilities:**

- Bidirectional communication between client and server via protobuf message streams
- Dynamic Groovy script sourcing from remote clients
- Custom ClassLoader integration for seamless resource resolution
- Multi-client support with execution context isolation
- Automatic class cache invalidation when remote sources are enabled

## Architecture

### High-Level Component Diagram

```
┌─────────────────────────────────────────────────────────────────────────┐
│                           CLIENT (Browser/Web)                          │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  ┌───────────────────────────────────────────────────────────────┐      │
│  │         JsRemoteFileSourceService (JavaScript/GWT)            │      │
│  ├───────────────────────────────────────────────────────────────┤      │
│  │ - Fetches plugin via Flight command                           │      │
│  │ - Establishes bidirectional MessageStream                     │      │
│  │ - Handles resource requests (EVENT_REQUEST_SOURCE)            │      │
│  │ - Sets execution context with resource paths                  │      │
│  │ - Responds with file content (String or Uint8Array)           │      │
│  └───────────────────────────────────────────────────────────────┘      │
│                                  │                                      │
│                                  │ Flight RPC / MessageStream           │
│                                  │ (Protobuf messages)                  │
└──────────────────────────────────┼──────────────────────────────────────┘
                                   │
┌──────────────────────────────────┼──────────────────────────────────────┐
│                                  ▼                                      │
│                        SERVER (Deephaven Core)                          │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  ┌───────────────────────────────────────────────────────────────┐      │
│  │      RemoteFileSourceCommandResolver (CommandResolver)        │      │
│  ├───────────────────────────────────────────────────────────────┤      │
│  │ - Handles Flight command: RemoteFileSourcePluginFetchRequest  │      │
│  │ - Exports PluginMarker for plugin connection                  │      │
│  │ - Returns FlightInfo with endpoint ticket                     │      │
│  └───────────────────────────────────────────────────────────────┘      │
│                                  │                                      │
│                                  ▼                                      │
│  ┌───────────────────────────────────────────────────────────────┐      │
│  │       RemoteFileSourcePlugin (ObjectType plugin)              │      │
│  ├───────────────────────────────────────────────────────────────┤      │
│  │ - Recognizes PluginMarker with matching plugin name           │      │
│  │ - Creates RemoteFileSourceMessageStream for each connection   │      │
│  │ - @AutoService(ObjectType.class)                              │      │
│  └───────────────────────────────────────────────────────────────┘      │
│                                  │                                      │
│                                  ▼                                      │
│  ┌───────────────────────────────────────────────────────────────┐      │
│  │   RemoteFileSourceMessageStream (MessageStream + Provider)    │      │
│  ├───────────────────────────────────────────────────────────────┤      │
│  │ - Implements bidirectional protobuf communication             │      │
│  │ - Implements RemoteFileSourceProvider interface               │      │
│  │ - Registers/unregisters with RemoteFileSourceClassLoader      │      │
│  │ - Manages execution context (active stream + resource paths)  │      │
│  │ - Requests resources from client on-demand                    │      │
│  │ - Tracks pending resource requests with CompletableFutures    │      │
│  └───────────────────────────────────────────────────────────────┘      │
│                                  │                                      │
│                                  │ registers as provider                │
│                                  ▼                                      │
│  ┌───────────────────────────────────────────────────────────────┐      │
│  │      RemoteFileSourceClassLoader (Custom ClassLoader)         │      │
│  ├───────────────────────────────────────────────────────────────┤      │
│  │ - Singleton initialized with parent ClassLoader               │      │
│  │ - Maintains list of registered RemoteFileSourceProviders      │      │
│  │ - Checks providers for resource availability via getResource()│      │
│  │ - Returns custom "remotefile://" URLs for remote resources    │      │
│  │ - Fetches resource bytes from provider on URL open            │      │
│  │ - 5-second timeout for resource fetching                      │      │
│  └───────────────────────────────────────────────────────────────┘      │
│                                  │                                      │
│                                  │ used by                              │
│                                  ▼                                      │
│  ┌───────────────────────────────────────────────────────────────┐      │
│  │          GroovyDeephavenSession (Script Engine)               │      │
│  ├───────────────────────────────────────────────────────────────┤      │
│  │ - Initializes RemoteFileSourceClassLoader as parent           │      │
│  │ - Checks hasConfiguredRemoteSources() before script exec      │      │
│  │ - Clears class cache when remote sources are/were active      │      │
│  │ - Groovy imports trigger getResource() -> remote fetch        │      │
│  └───────────────────────────────────────────────────────────────┘      │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

## Component Details

### Server Components

#### 1. RemoteFileSourceCommandResolver

**Location:** `plugin/remotefilesource/src/main/java/io.deephaven.remotefilesource/`

**Purpose:** Handles Flight commands for plugin fetching.

**Key Methods:**

- `flightInfoFor()` - Processes `RemoteFileSourcePluginFetchRequest` commands
- `fetchPlugin()` - Exports a `PluginMarker` singleton to specified ticket
- `handlesCommand()` - Identifies commands by type URL

**Flow:**

1. Client sends Flight command with `RemoteFileSourcePluginFetchRequest`
2. Resolver validates request has `result_id` ticket and `plugin_name`
3. Exports `PluginMarker.forPluginName(pluginName)` to session
4. Returns `FlightInfo` with endpoint containing the result ticket

#### 2. RemoteFileSourcePlugin

**Location:** `plugin/remotefilesource/src/main/java/io.deephaven.remotefilesource/`

**Purpose:** ObjectType plugin that creates message streams for remote file sourcing.

**Key Methods:**

- `name()` - Returns `"DeephavenRemoteFileSourcePlugin"`
- `isType()` - Checks if object is a `PluginMarker` with matching plugin name
- `compatibleClientConnection()` - Creates `RemoteFileSourceMessageStream` for connection

**Registration:** `@AutoService(ObjectType.class)`

#### 3. RemoteFileSourceMessageStream

**Location:** `plugin/remotefilesource/src/main/java/io.deephaven.remotefilesource/`

**Purpose:** Bidirectional message handler and remote file provider.

**Implements:**

- `ObjectType.MessageStream` - for bidirectional communication
- `RemoteFileSourceProvider` - for ClassLoader integration

**Key Features:**

- **Execution Context Management:** Static singleton context tracking active stream and resource paths
- **Provider Registration:** Auto-registers with `RemoteFileSourceClassLoader` on creation
- **Resource Requests:** Sends `RemoteFileSourceMetaRequest` to client, tracks with `CompletableFuture`
- **Active State:** Only services requests when `isActive()` returns true

**Message Handling:**

- `onData()` - Processes incoming `RemoteFileSourceClientRequest` messages
- `handleMetaResponse()` - Completes pending resource request futures
- `handleSetExecutionContext()` - Updates static execution context and sends acknowledgment
- `onClose()` - Cleans up: unregisters provider, clears context, cancels pending requests

**Static Methods:**

- `setExecutionContext(messageStream, resourcePaths)` - Sets active stream and resource paths
- `clearExecutionContext()` - Clears execution context

#### 4. RemoteFileSourceClassLoader

**Location:** `engine/base/src/main/java/io/deephaven/engine/util/`

**Purpose:** Custom ClassLoader that fetches resources from remote clients.

**Key Features:**

- **Singleton Pattern:** `initialize(parent)` must be called once before `getInstance()`
- **Provider Registration:** Multiple `RemoteFileSourceProvider` instances can register
- **Resource Resolution:** `getResource(name)` checks active providers before delegating to parent
- **Custom URL Protocol:** Returns `remotefile://` URLs for remote resources
- **Lazy Fetching:** Resource bytes fetched only when URL is opened
- **Timeout:** 5-second timeout for resource fetching

**Inner Classes:**

- `RemoteFileURLStreamHandler` - Creates connections for remote URLs
- `RemoteFileURLConnection` - Fetches resource bytes from provider on connect

**Integration:** Used as parent ClassLoader in `GroovyDeephavenSession.STATIC_LOADER`

#### 5. RemoteFileSourceProvider (Interface)

**Location:** `engine/base/src/main/java/io/deephaven/engine/util/`

**Purpose:** Contract for remote resource providers.

**Methods:**

- `canSourceResource(resourceName)` - Check if provider can handle resource
- `isActive()` - Check if provider is currently active
- `hasConfiguredResources()` - Check if provider has resource paths configured
- `requestResource(resourceName)` - Request resource bytes, returns `CompletableFuture<byte[]>`

#### 6. GroovyDeephavenSession Integration

**Location:** `engine/table/src/main/java/io/deephaven/engine/util/`

**Purpose:** Groovy script execution engine.

**Remote File Source Integration:**

- Initializes `RemoteFileSourceClassLoader` as parent of `STATIC_LOADER`
- Before each script execution, checks `hasConfiguredRemoteSources()`
- Clears class cache (`refreshClassLoader()`) when remote sources are/were active
- Tracks `previousEvalHadRemoteSources` to detect state changes

**Cache Invalidation Strategy:**

```java
// Clear cache if:
// 1. Previous execution had remote sources (files may have changed)
// 2. Current execution has remote sources (allow local cached classes to be remotely fetched)
if (previousEvalHadRemoteSources || hasRemoteSources) {
    refreshClassLoader();
}
```

#### 7. PluginMarker

**Location:** `plugin/src/main/java/io/deephaven/plugin/type/`

**Purpose:** Generic marker object for plugin exports.

**Key Features:**

- **Plugin Identification:** Contains `pluginName` field to distinguish different plugins
- **Singleton Per Plugin:** `forPluginName(name)` returns same instance for same name
- **Prevents Conflicts:** Without plugin name, first registered plugin using `PluginMarker` would intercept all instances

**Why Needed:** `ObjectTypeLookup.findObjectType()` returns the FIRST plugin where `isType()` returns true. The `pluginName` ensures plugins can distinguish their markers from others.

### Client Components

#### 1. JsRemoteFileSourceService

**Location:** `web/client-api/src/main/java/io/deephaven/web/client/api/remotefilesource/`

**Purpose:** JavaScript/GWT client for remote file source communication.

**Key Features:**

- **Plugin Fetching:** `fetchPlugin(connection)` - Static method to fetch plugin instance
- **Event-Driven:** Fires `EVENT_REQUEST_SOURCE` when server requests a resource
- **Single Listener Enforcement:** Only one listener allowed for `EVENT_REQUEST_SOURCE`
- **Execution Context:** `setExecutionContext(resourcePaths)` - Tells server which files to source remotely

**API Methods:**

```javascript
// Fetch the plugin (returns Promise<RemoteFileSourceService>)
RemoteFileSourceService.fetchPlugin(connection);

// Set execution context
service.setExecutionContext([
  'com/example/Script.groovy',
  'org/mycompany/Utils.groovy',
]);

// Listen for resource requests (MUST register exactly one listener)
service.addEventListener(EVENT_REQUEST_SOURCE, (event) => {
  const resourceName = event.detail.getResourceName();
  const content = event.detail.respond(content); // ... read file content ... // String, Uint8Array, or null
});

// Close connection
service.close();
```

**Message Handling:**

- `handleMetaRequest()` - Fires `EVENT_REQUEST_SOURCE` with `ResourceRequestEvent`
- `handleSetExecutionContextResponse()` - Resolves pending promise

**ResourceRequestEvent:**

- `getResourceName()` - Returns requested resource path
- `respond(content)` - Sends response to server (String UTF-8 encoded, Uint8Array as-is, or null for not found)

### Protocol Buffers

**Location:** `proto/proto-backplane-grpc/src/main/proto/deephaven_core/proto/remotefilesource.proto`

#### Message Types

**Server → Client:**

```protobuf
message RemoteFileSourceServerRequest {
  string request_id = 1;
  oneof request {
    RemoteFileSourceMetaRequest meta_request = 2;
    SetExecutionContextResponse set_execution_context_response = 3;
  }
}

message RemoteFileSourceMetaRequest {
  string resource_name = 1;  // e.g., "com/example/MyClass.groovy"
}

message SetExecutionContextResponse {
  bool success = 1;
}
```

**Client → Server:**

```protobuf
message RemoteFileSourceClientRequest {
  string request_id = 1;
  oneof request {
    RemoteFileSourceMetaResponse meta_response = 2;
    SetExecutionContextRequest set_execution_context = 3;
  }
}

message RemoteFileSourceMetaResponse {
  bytes content = 1;
  bool found = 2;
  string error = 3;
}

message SetExecutionContextRequest {
  repeated string resource_paths = 1;
}
```

**Flight Command (not via MessageStream):**

```protobuf
message RemoteFileSourcePluginFetchRequest {
  Ticket result_id = 1;
  string plugin_name = 2;
}
```

## Sequence Diagrams

### 1. Plugin Initialization and Connection

```
Client                     FlightService              CommandResolver              Plugin                MessageStream
  │                             │                            │                        │                         │
  │ getFlightInfo(              │                            │                        │                         │
  │   RemoteFileSource-         │                            │                        │                         │
  │   PluginFetchRequest)       │                            │                        │                         │
  ├────────────────────────────>│                            │                        │                         │
  │                             │ handlesCommand()?          │                        │                         │
  │                             ├───────────────────────────>│                        │                         │
  │                             │           true             │                        │                         │
  │                             │<───────────────────────────┤                        │                         │
  │                             │ flightInfoFor()            │                        │                         │
  │                             ├───────────────────────────>│                        │                         │
  │                             │                            │ session.newExport(     │                         │
  │                             │                            │   resultTicket,        │                         │
  │                             │                            │   PluginMarker)        │                         │
  │                             │                            ├───────────────────────>│                         │
  │                             │  FlightInfo(endpoint)      │                        │                         │
  │                             │<───────────────────────────┤                        │                         │
  │   FlightInfo                │                            │                        │                         │
  │<────────────────────────────┤                            │                        │                         │
  │                             │                            │                        │                         │
  │ connectToWidget(ticket)     │                            │                        │                         │
  ├──────────────────────────────────────────────────────────────────────────────────>│                         │
  │                             │                            │                        │ isType(PluginMarker)?   │
  │                             │                            │                        ├────────────────────────>│
  │                             │                            │                        │         true            │
  │                             │                            │                        │<────────────────────────┤
  │                             │                            │                        │ compatibleClientConn()  │
  │                             │                            │                        ├────────────────────────>│
  │                             │                            │                        │      creates            │
  │                             │                            │                        │<────────────────────────┤
  │                             │                            │                        │                         │
  │                             │                            │                        │   registerProvider()    │
  │                             │                            │                        │   with ClassLoader      │
  │                             │                            │                        ├────────────────────────>│
  │                             │                            │                        │                         │
  │◄────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ MessageStream established   │                            │                        │                         │
  │                             │                            │                        │                         │
```

### 2. Execution Context Setup and Script Execution

```
Client                JsRemoteFileSourceService    MessageStream            ClassLoader         GroovySession
  │                             │                         │                      │                     │
  │ setExecutionContext([       │                         │                      │                     │
  │   "myapp/Script.groovy"     │                         │                      │                     │
  │ ])                          │                         │                      │                     │
  ├────────────────────────────>│                         │                      │                     │
  │                             │ SetExecutionContext     │                      │                     │
  │                             │   Request               │                      │                     │
  │                             ├────────────────────────>│                      │                     │
  │                             │                         │ setExecutionContext( │                     │
  │                             │                         │   this, resourcePaths│                     │
  │                             │                         │ ) [static]           │                     │
  │                             │                         ├─────────────────────>│                     │
  │                             │                         │                      │                     │
  │                             │ SetExecutionContext     │                      │                     │
  │                             │   Response(success=true)│                      │                     │
  │                             │<────────────────────────┤                      │                     │
  │  Promise<true>              │                         │                      │                     │
  │<────────────────────────────┤                         │                      │                     │
  │                             │                         │                      │                     │
  │                             │                         │                      │ evaluateScript()    │
  │                             │                         │                      │<────────────────────┤
  │                             │                         │                      │                     │
  │                             │                         │                      │ hasConfiguredRemote │
  │                             │                         │                      │   Sources()?        │
  │                             │                         │                      ├────────────────────>│
  │                             │                         │                      │      true           │
  │                             │                         │                      │<────────────────────┤
  │                             │                         │                      │ refreshClassLoader()│
  │                             │                         │                      ├────────────────────>│
  │                             │                         │                      │                     │
  │                             │                         │                      │ compile & execute   │
  │                             │                         │                      │  (Groovy import     │
  │                             │                         │                      │   triggers resource │
  │                             │                         │                      │   lookup)           │
  │                             │                         │                      ├────────────────────>│
  │                             │                         │                      │                     │
```

### 3. Resource Request Flow

```
GroovyEngine        ClassLoader         MessageStream          JsService           Client (App/IDE)
    │                    │                    │                    │                       │
    │ import myapp.      │                    │                    │                       │
    │ Script             │                    │                    │                       │
    ├───────────────────>│                    │                    │                       │
    │                    │ getResource(       │                    │                       │
    │                    │  "myapp/Script.    │                    │                       │
    │                    │   groovy")         │                    │                       │
    │                    ├───────────────────>│                    │                       │
    │                    │                    │ isActive()?        │                       │
    │                    │                    │ canSourceResource()?                       │
    │                    │                    ├─ ─ ─ ─ ─ ─ ─ ─ ─ ─ │                       │
    │                    │  URL("remotefile://│     YES            │                       │
    │                    │    myapp/Script.   │                    │                       │
    │                    │     groovy")       │                    │                       │
    │                    │<───────────────────┤                    │                       │
    │                    │                    │                    │                       │
    │ url.openStream()   │                    │                    │                       │
    ├───────────────────>│                    │                    │                       │
    │                    │ connect()          │                    │                       │
    │                    ├───────────────────>│                    │                       │
    │                    │                    │ requestResource()  │                       │
    │                    │                    ├───────────────────>│                       │
    │                    │                    │                    │                       │
    │                    │                    │ MetaRequest(       │                       │
    │                    │                    │   requestId,       │                       │
    │                    │                    │   resourceName)    │                       │
    │                    │                    ├───────────────────>│                       │
    │                    │                    │                    │ EVENT_REQUEST_SOURCE  │
    │                    │                    │                    ├──────────────────────>│
    │                    │                    │                    │                       │
    │                    │                    │                    │                       │ (read file)
    │                    │                    │                    │                       ├─────────┐
    │                    │                    │                    │                       │         │
    │                    │                    │                    │                       │<────────┘
    │                    │                    │                    │ respond(content)      │
    │                    │                    │                    │<──────────────────────┤
    │                    │                    │ MetaResponse(      │                       │
    │                    │                    │   requestId,       │                       │
    │                    │                    │   content, found)  │                       │
    │                    │                    │<───────────────────┤                       │
    │                    │                    │ future.complete()  │                       │
    │                    │                    ├─ ─ ─ ─ ─ ─ ─ ─ ─ ─ │                       │
    │                    │ byte[] content     │                    │                       │
    │                    │   (from future.get)│                    │                       │
    │                    │<───────────────────┤                    │                       │
    │ InputStream        │                    │                    │                       │
    │<───────────────────┤                    │                    │                       │
    │                    │                    │                    │                       │
    │ (Groovy compiles   │                    │                    │                       │
    │  and executes)     │                    │                    │                       │
    ├───────────┐        │                    │                    │                       │
    │           │        │                    │                    │                       │
    │<──────────┘        │                    │                    │                       │
    │                    │                    │                    │                       │
```

## Key Design Patterns

### 1. Provider Pattern

`RemoteFileSourceProvider` interface allows multiple implementations to register with the ClassLoader. Currently only `RemoteFileSourceMessageStream` implements it, but the design supports future extensions.

### 2. Execution Context Isolation

The static `executionContext` in `RemoteFileSourceMessageStream` ensures:

- Only one message stream is active at a time
- Resource requests are routed to the correct client
- Multi-client scenarios work correctly (Community Core)

### 3. Lazy Resource Loading

Resources are only fetched when:

1. Groovy imports trigger `ClassLoader.getResource()`
2. The returned URL is opened
3. The `URLConnection.connect()` is called

This minimizes unnecessary network traffic.

### 4. Future-Based Async Communication

- `requestResource()` returns `CompletableFuture<byte[]>`
- Requests tracked by UUID
- Responses matched to requests via `request_id`
- 5-second timeout prevents hangs

### 5. Cache Invalidation Strategy

```
State Transition         Action
─────────────────────    ───────────────────────
none → remote            Clear cache (allow remote fetch)
remote → remote          Clear cache (files may have changed)
remote → none            Clear cache (restore local classes)
none → none              No cache clear (performance)
```

## File Inventory

### New Files Added

**Plugin:**

- `plugin/remotefilesource/build.gradle`
- `plugin/remotefilesource/gradle.properties`
- `plugin/remotefilesource/src/main/java/io.deephaven.remotefilesource/RemoteFileSourceCommandResolver.java`
- `plugin/remotefilesource/src/main/java/io.deephaven.remotefilesource/RemoteFileSourcePlugin.java`
- `plugin/remotefilesource/src/main/java/io.deephaven.remotefilesource/RemoteFileSourceMessageStream.java`
- `plugin/remotefilesource/src/main/java/io.deephaven.remotefilesource/RemoteFileSourceTicketResolverFactoryService.java`

**Engine:**

- `engine/base/src/main/java/io/deephaven/engine/util/RemoteFileSourceClassLoader.java`
- `engine/base/src/main/java/io/deephaven/engine/util/RemoteFileSourceProvider.java`
- `plugin/src/main/java/io/deephaven/plugin/type/PluginMarker.java`

**Web Client:**

- `web/client-api/src/main/java/io/deephaven/web/client/api/remotefilesource/JsRemoteFileSourceService.java`
- `web/client-api/src/main/java/io/deephaven/web/client/api/remotefilesource/ResourceContentUnion.java`
- `web/client-api/src/main/java/io/deephaven/web/client/api/JsProtobufUtils.java`

**Protocol:**

- `proto/proto-backplane-grpc/src/main/proto/deephaven_core/proto/remotefilesource.proto`
- `proto/raw-js-openapi/src/shim/remotefilesource_pb.js`

**Generated Proto Bindings:**

- Multiple files in `web/client-backplane/src/main/java/io/deephaven/javascript/proto/dhinternal/io/deephaven_core/proto/remotefilesource_pb/`

### Modified Files

**Engine Integration:**

- `engine/table/src/main/java/io/deephaven/engine/util/GroovyDeephavenSession.java`
  - Initialize `RemoteFileSourceClassLoader` as parent
  - Check `hasConfiguredRemoteSources()` before execution
  - Clear class cache when remote sources are/were active
  - Track `previousEvalHadRemoteSources` state

- `engine/table/src/main/java/io/deephaven/engine/util/AbstractScriptSession.java`
  - (Minor changes for cache clearing support)

**Server Configuration:**

- `server/build.gradle` - Added remotefilesource plugin dependency
- `server/jetty-app/build.gradle` - Runtime dependencies
- `server/jetty-app-11/build.gradle` - Runtime dependencies

**Web Client Integration:**

- `web/client-api/src/main/java/io/deephaven/web/client/api/CoreClient.java`
  - Integration points for remote file source service

**Build Configuration:**

- `settings.gradle` - Added remotefilesource plugin project
- `proto/proto-backplane-grpc/Dockerfile` - Proto generation
- `proto/raw-js-openapi/webpack.config.js` - JS proto bundling
- `proto/raw-js-openapi/src/index.js` - Proto exports

## Usage Example

### Client-Side (JavaScript)

```javascript
// 1. Fetch the plugin
const remoteFileSourceService =
  await dh.remotefilesource.RemoteFileSourceService.fetchPlugin(connection);

// 2. Register resource request handler (REQUIRED - exactly one listener)
remoteFileSourceService.addEventListener(
  dh.remotefilesource.RemoteFileSourceService.EVENT_REQUEST_SOURCE,
  (event) => {
    const resourceName = event.detail.getResourceName();
    console.log(`Server requested: ${resourceName}`);

    // Read file from local file system, IDE, or other source
    const content = readFile(resourceName); // String or Uint8Array

    // Respond with content (or null if not found)
    event.detail.respond(content);
  },
);

// 3. Set execution context with resource paths
await remoteFileSourceService.setExecutionContext([
  'com/example/MyScript.groovy',
  'com/example/utils/Helper.groovy',
]);

// 4. Now execute script on server
// When script imports these files, server will request them from client
await session.runCode(`
    import com.example.MyScript
    import com.example.utils.Helper
    
    def script = new MyScript()
    script.run()
`);

// 5. Clean up when done
remoteFileSourceService.close();
```

### Server-Side (Groovy Script)

The remote file sourcing is transparent to Groovy scripts:

```groovy
// This import triggers remote file fetch if configured
import com.example.MyScript
import com.example.utils.Helper

// Use the classes as if they were local
def script = new MyScript()
def helper = new Helper()

script.doSomething()
helper.assist()
```

## Multi-Client Considerations

The design supports multiple simultaneous clients (important for Community Core):

1. **Each client connection** gets its own `RemoteFileSourceMessageStream` instance
2. **Execution context** is global but only one stream can be active at a time
3. **Before script execution**, client calls `setExecutionContext()` to make its stream active
4. **During script execution**, only the active stream's resources are used
5. **After script execution**, context can be cleared or set to another stream

This ensures:

- Client A's scripts don't accidentally fetch resources from Client B
- Multiple clients can connect without interference
- Resource requests are routed to the correct client

## Performance Considerations

### Class Cache Management

- **Problem:** Groovy caches compiled classes; remote files may change
- **Solution:** Clear class cache when remote sources are/were enabled
- **Trade-off:** Performance hit on each execution with remote sources
- **Future optimization:** Selective cache invalidation based on file hashes

### Resource Fetching

- **Lazy loading:** Resources only fetched when needed (import time, not connection time)
- **Timeout:** 5-second timeout prevents indefinite hangs
- **Single request:** Each resource requested at most once per execution

### Network Overhead

- **Protobuf:** Efficient binary serialization
- **Bidirectional stream:** Reuses single connection for all messages
- **No polling:** Event-driven, no wasted bandwidth

## Security Considerations

1. **Authentication:** Relies on existing Deephaven session authentication
2. **Authorization:** Server trusts authenticated clients to provide valid code
3. **Code Execution:** Remote files execute with full server permissions
4. **Resource Path Validation:** Server validates resource names (.groovy files only)
5. **Timeout Protection:** 5-second timeout prevents DoS via hanging requests

**Important:** This feature is designed for trusted environments. Remote code execution inherently has security implications.

## Future Enhancements

### Potential Improvements

1. **File change detection:** Hash-based cache invalidation instead of clearing all
2. **Resource prefetching:** Fetch all declared resources at context setup time
3. **Compression:** Compress large resource payloads
4. **Multiple languages:** Support Python, R, or other scripting languages
5. **Resource caching:** Cache resources client-side to avoid redundant reads
6. **Incremental compilation:** Only recompile changed files
7. **Watch mode:** Auto-refresh when local files change

### Alternative Approaches Considered

1. **File upload:** Requires explicit upload step, less seamless
2. **Virtual filesystem:** More complex, broader scope
3. **Shared network drive:** Requires infrastructure, not browser-friendly
4. **Polling:** Less efficient than bidirectional stream
5. **HTTP endpoints:** More overhead than Flight/MessageStream

## Testing Strategy

### Unit Tests

- `RemoteFileSourceClassLoader` resource resolution
- `PluginMarker` singleton behavior
- Protobuf message serialization/deserialization

### Integration Tests

- End-to-end plugin fetch → resource request → script execution
- Multiple clients with execution context switching
- Timeout handling and error cases
- Cache invalidation behavior

### Manual Testing

- Web IDE integration with local file system
- Large file transfer performance
- Network interruption resilience
- Multi-user scenarios

## Related Documentation

- **Arrow Flight Protocol:** https://arrow.apache.org/docs/format/Flight.html
- **Deephaven Plugin System:** (internal docs)
- **Groovy ClassLoader:** https://docs.groovy-lang.org/latest/html/api/groovy/lang/GroovyClassLoader.html
- **Protocol Buffers:** https://protobuf.dev/

## Revision History

| Date       | Author   | Changes                         |
| ---------- | -------- | ------------------------------- |
| 2026-02-25 | AI Agent | Initial design document created |

---

_This document describes the implementation on branch `DH-20578_groovy-remote-file-sourcing`._
