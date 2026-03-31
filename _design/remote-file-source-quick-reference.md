# Remote File Source - Quick Reference

## For Client Developers

### Basic Setup (JavaScript)

```javascript
// 1. Import the service
import { remotefilesource } from '@deephaven/jsapi';

// 2. Fetch the plugin instance
const service = await remotefilesource.RemoteFileSourceService.fetchPlugin(connection);

// 3. Register ONE resource request handler (REQUIRED)
service.addEventListener(
    remotefilesource.RemoteFileSourceService.EVENT_REQUEST_SOURCE,
    (event) => {
        const resourceName = event.detail.getResourceName();
        
        // Read the file from your local file system, IDE, etc.
        const content = await readLocalFile(resourceName);
        
        // Respond with content (String, Uint8Array) or null if not found
        event.detail.respond(content);
    }
);

// 4. Set execution context before running script
await service.setExecutionContext([
    "com/example/MyScript.groovy",
    "com/example/utils/Helper.groovy"
]);

// 5. Execute your script (imports will trigger resource requests)
await session.runCode(`
    import com.example.MyScript
    script = new MyScript()
    script.run()
`);

// 6. Clean up (optional - clear execution context)
await service.setExecutionContext([]); // or null

// 7. Close when done
service.close();
```

### Important Notes

- **Single Listener:** Only ONE listener allowed for `EVENT_REQUEST_SOURCE` per service instance
- **Response Required:** MUST call `event.detail.respond()` for every request
- **File Format:** Only `.groovy` files are sourced remotely
- **Path Format:** Use forward slashes, package-style paths (e.g., `com/example/Script.groovy`)
- **Timing:** Set execution context BEFORE executing script
- **String Encoding:** String content is UTF-8 encoded automatically
- **Not Found:** Respond with `null` if file doesn't exist

### TypeScript Types

```typescript
interface ResourceRequestEvent {
    getResourceName(): string;
    respond(content: string | Uint8Array | null): void;
}

class RemoteFileSourceService {
    static fetchPlugin(connection: WorkerConnection): Promise<RemoteFileSourceService>;
    setExecutionContext(resourcePaths?: string[] | null): Promise<boolean>;
    addEventListener<T>(name: string, callback: (event: Event<T>) => void): RemoverFn;
    close(): void;
    
    static readonly EVENT_REQUEST_SOURCE: string;
}
```

### Error Handling

```javascript
try {
    const service = await RemoteFileSourceService.fetchPlugin(connection);
    
    service.addEventListener(EVENT_REQUEST_SOURCE, async (event) => {
        try {
            const content = await readFile(event.detail.getResourceName());
            event.detail.respond(content);
        } catch (error) {
            console.error('Failed to read file:', error);
            event.detail.respond(null); // Respond with not found
        }
    });
    
    const success = await service.setExecutionContext(paths);
    if (!success) {
        console.error('Failed to set execution context');
    }
} catch (error) {
    console.error('Remote file source setup failed:', error);
}
```

---

## For Server Plugin Developers

### Extending RemoteFileSourceProvider

```java
public class MyCustomProvider implements RemoteFileSourceProvider {
    @Override
    public boolean canSourceResource(String resourceName) {
        // Check if this provider can handle the resource
        return resourceName.endsWith(".groovy") && isConfiguredFor(resourceName);
    }
    
    @Override
    public boolean isActive() {
        // Check if this provider should be used right now
        return myExecutionContext != null && myExecutionContext.isActive();
    }
    
    @Override
    public boolean hasConfiguredResources() {
        // Check if this provider has resources configured
        return !myResourcePaths.isEmpty();
    }
    
    @Override
    public CompletableFuture<byte[]> requestResource(String resourceName) {
        // Fetch the resource asynchronously
        CompletableFuture<byte[]> future = new CompletableFuture<>();
        
        // Your custom logic to fetch resource
        myResourceFetcher.fetch(resourceName)
            .thenAccept(content -> future.complete(content))
            .exceptionally(error -> {
                future.completeExceptionally(error);
                return null;
            });
        
        return future;
    }
}
```

### Registering with ClassLoader

```java
// Get the singleton ClassLoader instance
RemoteFileSourceClassLoader classLoader = RemoteFileSourceClassLoader.getInstance();

// Register your provider
MyCustomProvider provider = new MyCustomProvider();
classLoader.registerProvider(provider);

// Unregister when done
classLoader.unregisterProvider(provider);
```

### Checking Remote Sources in Script Session

```java
RemoteFileSourceClassLoader classLoader = RemoteFileSourceClassLoader.getInstance();

if (classLoader.hasConfiguredRemoteSources()) {
    // Clear class cache to allow remote fetching
    refreshClassLoader();
}

// Execute script...
```

---

## For Groovy Script Authors

Remote file sourcing is transparent - just use normal imports:

```groovy
// These imports automatically trigger remote fetching if configured
import com.example.MyScript
import com.example.utils.Helper
import static com.example.Constants.*

// Use the classes normally
def script = new MyScript()
script.run()

def helper = new Helper()
helper.doSomething()
```

**No special syntax required!** The ClassLoader handles everything.

---

## Configuration Reference

### Plugin Name
Must match across client and server:
- **Server:** `RemoteFileSourcePlugin.name()` returns `"DeephavenRemoteFileSourcePlugin"`
- **Client:** `PLUGIN_NAME = "DeephavenRemoteFileSourcePlugin"`

### Timeouts
- **Resource Fetch:** 5 seconds (server-side in `RemoteFileSourceClassLoader`)
- **Set Execution Context:** 30 seconds (client-side in `JsRemoteFileSourceService`)

### Resource Path Format
- **Correct:** `com/example/Script.groovy`
- **Correct:** `utils/Helper.groovy`
- **Wrong:** `com.example.Script.groovy` (dots instead of slashes)
- **Wrong:** `/com/example/Script.groovy` (leading slash)
- **Wrong:** `Script.groovy` (missing package path, unless really in default package)

---

## Debugging

### Enable Debug Logging (Server)

Add to your logging configuration:
```properties
io.deephaven.remotefilesource.level=DEBUG
io.deephaven.engine.util.RemoteFileSourceClassLoader.level=DEBUG
```

### Check Execution Context (Server)

```java
RemoteFileSourceClassLoader classLoader = RemoteFileSourceClassLoader.getInstance();
System.out.println("Has remote sources: " + classLoader.hasConfiguredRemoteSources());
```

### Verify Provider Registration (Server)

The `RemoteFileSourceMessageStream` logs:
- `"Registered RemoteFileSourceMessageStream provider with RemoteFileSourceClassLoader"`
- `"Unregistered RemoteFileSourceMessageStream provider from RemoteFileSourceClassLoader"`

### Trace Resource Requests (Server)

Look for log messages:
- `"Can source: <resourceName>"` - Provider can handle resource
- `"Requesting resource: <resourceName>"` - Sending request to client
- `"Received resource response for requestId: <id>, found: <true/false>, content length: <bytes>"`

### Client-Side Debugging

```javascript
service.addEventListener(EVENT_REQUEST_SOURCE, (event) => {
    console.log('Resource requested:', event.detail.getResourceName());
    
    const content = readFile(event.detail.getResourceName());
    console.log('Responding with', content ? content.length : 0, 'bytes');
    
    event.detail.respond(content);
});
```

---

## Common Issues

### Issue: "No listener registered for EVENT_REQUEST_SOURCE"
**Cause:** Client didn't register a listener before server requested resource  
**Fix:** Register listener immediately after `fetchPlugin()`, before setting execution context

### Issue: "EVENT_REQUEST_SOURCE already has a listener"
**Cause:** Attempted to register multiple listeners  
**Fix:** Only register ONE listener per service instance

### Issue: Resource not found / timeout
**Cause:** 
- Client responded with `null`
- Client didn't respond within 5 seconds
- Client listener threw an error

**Fix:** 
- Ensure file path is correct
- Check client can read the file
- Add error handling in client listener
- Verify client responds for every request

### Issue: Class not found even with remote source
**Cause:** 
- Execution context not set
- Resource path doesn't match import
- File not `.groovy` extension

**Fix:**
- Call `setExecutionContext()` with correct paths
- Use package-style paths: `com/example/Script.groovy`
- Only `.groovy` files are sourced remotely

### Issue: Changes to local files not reflected
**Cause:** Class cache not cleared  
**Fix:** This should happen automatically. If not, check:
- `hasConfiguredRemoteSources()` returns true
- Cache invalidation logic in `GroovyDeephavenSession`

---

## Performance Tips

### Minimize Resource Paths
Only include files that actually need to be sourced remotely:
```javascript
// Good: Only include files you'll import
await service.setExecutionContext([
    "com/example/MyScript.groovy"
]);

// Bad: Including unnecessary files
await service.setExecutionContext([
    "com/example/MyScript.groovy",
    "com/example/UnusedFile.groovy",  // Not imported, waste of config
]);
```

### Cache File Content
If executing multiple scripts with same imports:
```javascript
const fileCache = new Map();

service.addEventListener(EVENT_REQUEST_SOURCE, (event) => {
    const resourceName = event.detail.getResourceName();
    
    if (!fileCache.has(resourceName)) {
        fileCache.set(resourceName, readFile(resourceName));
    }
    
    event.detail.respond(fileCache.get(resourceName));
});
```

### Use Binary Format for Large Files
```javascript
// More efficient for large files
const content = await readFileAsUint8Array(resourceName);
event.detail.respond(content); // Uint8Array - no encoding needed
```

### Clear Context When Not Needed
```javascript
// After execution, clear context to avoid cache clearing
await service.setExecutionContext([]);
```

---

## Testing Checklist

### Client Tests
- [ ] Plugin fetch succeeds
- [ ] Event listener registration works
- [ ] Single listener enforcement works
- [ ] Set execution context succeeds
- [ ] Resource request event fires
- [ ] Response with String works
- [ ] Response with Uint8Array works
- [ ] Response with null works
- [ ] Multiple requests handled correctly
- [ ] Close cleans up properly

### Server Tests
- [ ] Command resolver handles fetch request
- [ ] Plugin creates message stream
- [ ] Provider registers with ClassLoader
- [ ] Execution context sets correctly
- [ ] Resource request sent to client
- [ ] Response received and completed
- [ ] Timeout works (5 seconds)
- [ ] Multiple providers handled correctly
- [ ] Active provider selected correctly
- [ ] Cache cleared when remote sources enabled
- [ ] Provider unregisters on close

### Integration Tests
- [ ] End-to-end: fetch → set context → execute → resource request → response
- [ ] Groovy import triggers remote fetch
- [ ] Class compiles from remote source
- [ ] Script executes successfully
- [ ] Multiple files imported correctly
- [ ] File not found handled gracefully
- [ ] Multi-client scenario works (execution context switching)

---

## Quick Troubleshooting Guide

| Symptom | Check | Solution |
|---------|-------|----------|
| Plugin fetch fails | Network, auth | Verify connection is authenticated |
| No resource requests | Execution context | Call `setExecutionContext()` before script |
| Class not found | Path format | Use `com/example/Script.groovy` not `com.example.Script.groovy` |
| Timeout | Client handler | Ensure client responds within 5 seconds |
| Multiple listeners error | Event registration | Only register one listener |
| Changes not reflected | Cache | Automatic, but verify `hasConfiguredRemoteSources()` |
| Wrong file requested | Resource paths | Verify paths in `setExecutionContext()` match imports |

---

## API Summary

### Client API (JavaScript)

```typescript
// Static method
RemoteFileSourceService.fetchPlugin(connection: WorkerConnection): Promise<RemoteFileSourceService>

// Instance methods
setExecutionContext(resourcePaths?: string[]): Promise<boolean>
addEventListener(name: string, callback: EventFn): RemoverFn
close(): void

// Events
EVENT_REQUEST_SOURCE = "requestsource"

// Event detail
ResourceRequestEvent {
    getResourceName(): string
    respond(content: string | Uint8Array | null): void
}
```

### Server API (Java)

```java
// ClassLoader
RemoteFileSourceClassLoader.initialize(ClassLoader parent): RemoteFileSourceClassLoader
RemoteFileSourceClassLoader.getInstance(): RemoteFileSourceClassLoader
void registerProvider(RemoteFileSourceProvider provider)
void unregisterProvider(RemoteFileSourceProvider provider)
boolean hasConfiguredRemoteSources()
URL getResource(String name)

// Provider Interface
boolean canSourceResource(String resourceName)
boolean isActive()
boolean hasConfiguredResources()
CompletableFuture<byte[]> requestResource(String resourceName)

// MessageStream
static void setExecutionContext(RemoteFileSourceMessageStream messageStream, List<String> resourcePaths)
static void clearExecutionContext()
```

### Protocol Buffers

```protobuf
// Flight command
RemoteFileSourcePluginFetchRequest {
  Ticket result_id = 1;
  string plugin_name = 2;
}

// Client → Server
RemoteFileSourceClientRequest {
  string request_id = 1;
  oneof request {
    RemoteFileSourceMetaResponse meta_response = 2;
    SetExecutionContextRequest set_execution_context = 3;
  }
}

// Server → Client  
RemoteFileSourceServerRequest {
  string request_id = 1;
  oneof request {
    RemoteFileSourceMetaRequest meta_request = 2;
    SetExecutionContextResponse set_execution_context_response = 3;
  }
}
```

---

**Last Updated:** February 25, 2026  
**Branch:** DH-20578_groovy-remote-file-sourcing

