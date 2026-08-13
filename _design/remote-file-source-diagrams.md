# Remote File Source - Visual Diagrams

This document contains Mermaid diagrams for the Remote File Source feature. These diagrams can be rendered in GitHub, GitLab, or any Mermaid-compatible viewer.

## System Architecture

```mermaid
graph TB
    subgraph "Client (Browser)"
        JS[JsRemoteFileSourceService]
        IDE[IDE/File System]
    end
    
    subgraph "Server (Deephaven Core)"
        subgraph "Plugin Layer"
            CR[RemoteFileSourceCommandResolver]
            PL[RemoteFileSourcePlugin]
            MS[RemoteFileSourceMessageStream]
        end
        
        subgraph "Engine Layer"
            CL[RemoteFileSourceClassLoader]
            GS[GroovyDeephavenSession]
        end
    end
    
    JS -->|Flight Command| CR
    CR -->|Export PluginMarker| PL
    PL -->|Create| MS
    MS -->|Register Provider| CL
    JS <-->|Bidirectional MessageStream| MS
    CL -->|getResource| MS
    GS -->|Use as Parent| CL
    MS -->|Request Resource| JS
    JS -->|Read File| IDE
    IDE -->|File Content| JS
```

## Component Class Diagram

```mermaid
classDiagram
    class RemoteFileSourceCommandResolver {
        <<CommandResolver>>
        +flightInfoFor() ExportObject~FlightInfo~
        +handlesCommand() boolean
        -fetchPlugin() ExportObject~FlightInfo~
        -parseFetchRequest() RemoteFileSourcePluginFetchRequest
    }
    
    class RemoteFileSourcePlugin {
        <<ObjectType>>
        +name() String
        +isType() boolean
        +compatibleClientConnection() MessageStream
    }
    
    class RemoteFileSourceMessageStream {
        <<MessageStream, RemoteFileSourceProvider>>
        -connection: MessageStream
        -pendingRequests: Map~String,CompletableFuture~
        +static executionContext: RemoteFileSourceExecutionContext
        +onData() void
        +onClose() void
        +canSourceResource() boolean
        +isActive() boolean
        +requestResource() CompletableFuture~byte[]~
        +static setExecutionContext() void
        +static clearExecutionContext() void
    }
    
    class RemoteFileSourceClassLoader {
        <<Singleton>>
        -instance: RemoteFileSourceClassLoader
        -providers: List~RemoteFileSourceProvider~
        +static initialize() RemoteFileSourceClassLoader
        +static getInstance() RemoteFileSourceClassLoader
        +registerProvider() void
        +unregisterProvider() void
        +getResource() URL
        +hasConfiguredRemoteSources() boolean
    }
    
    class RemoteFileSourceProvider {
        <<interface>>
        +canSourceResource() boolean
        +isActive() boolean
        +hasConfiguredResources() boolean
        +requestResource() CompletableFuture~byte[]~
    }
    
    class PluginMarker {
        -pluginName: String
        +static forPluginName() PluginMarker
        +getPluginName() String
    }
    
    class GroovyDeephavenSession {
        -groovyShell: DeephavenGroovyShell
        -previousEvalHadRemoteSources: boolean
        +evaluateScript() void
        -refreshClassLoader() void
    }
    
    class JsRemoteFileSourceService {
        -widget: JsWidget
        -pendingSetExecutionContextRequests: Map
        +static fetchPlugin() Promise~JsRemoteFileSourceService~
        +setExecutionContext() Promise~Boolean~
        +addEventListener() RemoverFn
        +close() void
        -handleMessage() void
        -handleMetaRequest() void
        -handleSetExecutionContextResponse() void
    }
    
    RemoteFileSourceCommandResolver --> PluginMarker : exports
    RemoteFileSourcePlugin --> RemoteFileSourceMessageStream : creates
    RemoteFileSourceMessageStream ..|> RemoteFileSourceProvider : implements
    RemoteFileSourceMessageStream --> RemoteFileSourceClassLoader : registers with
    RemoteFileSourceClassLoader --> RemoteFileSourceProvider : uses
    GroovyDeephavenSession --> RemoteFileSourceClassLoader : parent ClassLoader
    JsRemoteFileSourceService --> RemoteFileSourceMessageStream : communicates with
```

## Sequence: Initial Connection Setup

```mermaid
sequenceDiagram
    participant C as Client
    participant F as FlightService
    participant CR as CommandResolver
    participant S as Session
    participant P as Plugin
    participant MS as MessageStream
    participant CL as ClassLoader
    
    C->>F: getFlightInfo(RemoteFileSourcePluginFetchRequest)
    F->>CR: handlesCommand(descriptor)?
    CR-->>F: true
    F->>CR: flightInfoFor(descriptor)
    CR->>S: newExport(ticket, PluginMarker)
    S-->>CR: export created
    CR-->>F: FlightInfo(endpoint with ticket)
    F-->>C: FlightInfo
    
    C->>P: connect(ticket)
    P->>P: isType(PluginMarker)?
    P->>MS: compatibleClientConnection(PluginMarker)
    MS->>CL: registerProvider(this)
    CL-->>MS: registered
    MS-->>P: new MessageStream
    P-->>C: MessageStream established
```

## Sequence: Execution Context and Script Execution

```mermaid
sequenceDiagram
    participant C as Client
    participant JS as JsService
    participant MS as MessageStream
    participant CL as ClassLoader
    participant GS as GroovySession
    
    C->>JS: setExecutionContext(["myapp/Script.groovy"])
    JS->>MS: SetExecutionContextRequest
    MS->>MS: setExecutionContext(this, paths)<br/>[static]
    MS->>JS: SetExecutionContextResponse(success=true)
    JS-->>C: Promise resolved
    
    Note over C,GS: Client executes script with import
    
    C->>GS: evaluateScript("import myapp.Script")
    GS->>CL: hasConfiguredRemoteSources()?
    CL-->>GS: true
    GS->>GS: refreshClassLoader()<br/>(clear cache)
    GS->>GS: compile script
    
    Note over GS,CL: Groovy import triggers resource lookup
    
    GS->>CL: getResource("myapp/Script.groovy")
    CL->>MS: canSourceResource("myapp/Script.groovy")?
    MS-->>CL: true (isActive && matches path)
    CL-->>GS: URL("remotefile://myapp/Script.groovy")
```

## Sequence: Resource Fetch Flow

```mermaid
sequenceDiagram
    participant GE as Groovy Engine
    participant CL as ClassLoader
    participant MS as MessageStream
    participant JS as JsService
    participant FS as Client FileSystem
    
    GE->>CL: url.openStream()
    CL->>CL: URLConnection.connect()
    CL->>MS: requestResource("myapp/Script.groovy")
    
    Note over MS: Generate UUID requestId<br/>Create CompletableFuture<br/>Store in pendingRequests
    
    MS->>JS: RemoteFileSourceServerRequest<br/>{requestId, MetaRequest{resourceName}}
    JS->>JS: fireEvent(EVENT_REQUEST_SOURCE)
    JS->>FS: User handler reads file
    FS-->>JS: file content
    JS->>MS: RemoteFileSourceClientRequest<br/>{requestId, MetaResponse{content, found}}
    
    MS->>MS: future.complete(content)
    MS-->>CL: byte[] (from future.get())
    CL-->>GE: InputStream
    
    Note over GE: Groovy compiles<br/>and executes
```

## State Diagram: MessageStream Lifecycle

```mermaid
stateDiagram-v2
    [*] --> Created: compatibleClientConnection()
    Created --> Registered: registerProvider()
    Registered --> Inactive: (no execution context)
    Registered --> Active: setExecutionContext(this, paths)
    Active --> Inactive: clearExecutionContext()
    Inactive --> Active: setExecutionContext(this, paths)
    Active --> ServicingRequest: requestResource() called
    ServicingRequest --> Active: response received
    Active --> Closed: onClose()
    Inactive --> Closed: onClose()
    Closed --> [*]: unregisterProvider()
    
    note right of Active
        isActive() = true
        Can service resource requests
    end note
    
    note right of Inactive
        isActive() = false
        Cannot service resource requests
    end note
```

## State Diagram: Cache Management

```mermaid
stateDiagram-v2
    [*] --> NoRemoteSources
    NoRemoteSources --> RemoteSourcesEnabled: setExecutionContext(paths)
    RemoteSourcesEnabled --> NoRemoteSources: clearExecutionContext()
    
    NoRemoteSources --> CheckPrevious: evaluateScript()
    RemoteSourcesEnabled --> ClearCache: evaluateScript()
    
    CheckPrevious --> ClearCache: previousEvalHadRemoteSources = true
    CheckPrevious --> KeepCache: previousEvalHadRemoteSources = false
    
    ClearCache --> RemoteSourcesEnabled: after eval (if still enabled)
    ClearCache --> NoRemoteSources: after eval (if cleared)
    KeepCache --> NoRemoteSources: after eval
    
    note right of ClearCache
        refreshClassLoader()
        Evicts all Groovy classes
        Allows re-compilation
    end note
    
    note right of KeepCache
        No cache clear
        Better performance
        Local classes only
    end note
```

## Data Flow: Protobuf Messages

```mermaid
flowchart LR
    subgraph "Client→Server"
        C1[RemoteFileSourceClientRequest]
        C2[SetExecutionContextRequest]
        C3[RemoteFileSourceMetaResponse]
        
        C1 --> C2
        C1 --> C3
    end
    
    subgraph "Server→Client"
        S1[RemoteFileSourceServerRequest]
        S2[RemoteFileSourceMetaRequest]
        S3[SetExecutionContextResponse]
        
        S1 --> S2
        S1 --> S3
    end
    
    subgraph "Flight Command"
        F1[RemoteFileSourcePluginFetchRequest]
        F2[Ticket: result_id]
        F3[String: plugin_name]
        
        F1 --> F2
        F1 --> F3
    end
    
    style C1 fill:#e1f5ff
    style S1 fill:#fff4e1
    style F1 fill:#f0e1ff
```

## Activity Diagram: Complete Workflow

```mermaid
flowchart TD
    Start([User wants to execute<br/>local Groovy script])
    
    Start --> FetchPlugin[Client: Fetch plugin via<br/>RemoteFileSourcePluginFetchRequest]
    FetchPlugin --> RegisterListener[Client: Register EVENT_REQUEST_SOURCE<br/>listener]
    RegisterListener --> SetContext[Client: Call setExecutionContext<br/>with resource paths]
    SetContext --> ContextSet{Context set<br/>successfully?}
    
    ContextSet -->|No| Error1([Error: Context setup failed])
    ContextSet -->|Yes| ExecuteScript[User: Execute script<br/>with imports]
    
    ExecuteScript --> CheckRemote{GroovySession:<br/>hasConfiguredRemoteSources?}
    CheckRemote -->|No| LocalExec[Execute with local<br/>classes only]
    CheckRemote -->|Yes| ClearCache[Clear Groovy class cache]
    
    ClearCache --> Compile[Compile script]
    Compile --> Import{Import<br/>encountered?}
    
    Import -->|Yes| GetResource[ClassLoader.getResource]
    GetResource --> CanSource{Provider.canSourceResource?}
    
    CanSource -->|No| DelegateParent[Delegate to parent<br/>ClassLoader]
    CanSource -->|Yes| RequestRemote[Provider.requestResource]
    
    RequestRemote --> SendRequest[Send MetaRequest<br/>to client]
    SendRequest --> WaitResponse{Wait for response<br/>5 sec timeout}
    
    WaitResponse -->|Timeout| Error2([Error: Request timeout])
    WaitResponse -->|Response| ReceiveContent[Receive MetaResponse<br/>with content]
    
    ReceiveContent --> Found{Resource<br/>found?}
    Found -->|No| Error3([Error: Resource not found])
    Found -->|Yes| ReturnStream[Return InputStream<br/>with content]
    
    ReturnStream --> CompileClass[Groovy: Compile class<br/>from source]
    DelegateParent --> CompileClass
    
    CompileClass --> Import
    Import -->|No more| Execute[Execute compiled script]
    LocalExec --> Execute
    
    Execute --> Done([Script execution complete])
    
    style Start fill:#e1f5ff
    style Done fill:#e1ffe1
    style Error1 fill:#ffe1e1
    style Error2 fill:#ffe1e1
    style Error3 fill:#ffe1e1
```

## Component Dependencies

```mermaid
graph TD
    subgraph "Web Client Module"
        WC[web/client-api]
        WCB[web/client-backplane]
    end
    
    subgraph "Plugin Module"
        PL[plugin/remotefilesource]
        PM[plugin core<br/>PluginMarker]
    end
    
    subgraph "Engine Module"
        EB[engine/base<br/>RemoteFileSourceClassLoader]
        ET[engine/table<br/>GroovyDeephavenSession]
    end
    
    subgraph "Proto Module"
        PB[proto/proto-backplane-grpc]
        PR[proto/raw-js-openapi]
    end
    
    subgraph "Server Module"
        SV[server/jetty-app]
    end
    
    WC -->|uses| WCB
    WC -->|proto| PB
    WC -->|js proto| PR
    
    PL -->|uses| PM
    PL -->|proto| PB
    PL -->|uses| EB
    
    ET -->|uses| EB
    
    SV -->|runtime dep| PL
    
    PB -->|generates| WCB
    PB -->|generates| PR
    
    style WC fill:#e1f5ff
    style PL fill:#ffe1f5
    style EB fill:#f5ffe1
    style PB fill:#fff4e1
```

## Message Flow Timing

```mermaid
gantt
    title Remote File Source Request Timeline
    dateFormat X
    axisFormat %L ms
    
    section Client
    Fire setExecutionContext :a1, 0, 50
    Wait for ack :a2, 50, 100
    Execute script :a3, 100, 150
    Receive resource request :a4, 250, 300
    Read file :a5, 300, 450
    Send response :a6, 450, 500
    
    section Network
    Context request transit :b1, 50, 75
    Context ack transit :b2, 125, 150
    Resource request transit :b3, 200, 250
    Resource response transit :b4, 500, 550
    
    section Server
    Receive context request :c1, 75, 100
    Send context ack :c2, 100, 125
    Start script compilation :c3, 150, 200
    Send resource request :c4, 200, 250
    Wait for response :c5, 250, 550
    Complete compilation :c6, 550, 600
    Execute script :c7, 600, 700
```

---

**Note:** These diagrams can be viewed in:
- GitHub/GitLab (native Mermaid rendering)
- VS Code (with Mermaid extension)
- Online: https://mermaid.live/
- IntelliJ IDEA (with Mermaid plugin)

