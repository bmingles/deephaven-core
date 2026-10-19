# Remote File Source Feature Documentation

This directory contains comprehensive documentation for the Remote File Source feature implemented in branch `DH-20578_groovy-remote-file-sourcing`.

## Documents

### [remote-file-source.md](./remote-file-source.md)
**Main design document** - Complete architectural overview including:
- Feature overview and key capabilities
- High-level component diagram
- Detailed component descriptions (server and client)
- Protocol buffer message definitions
- Sequence diagrams (ASCII art)
- Design patterns and architectural decisions
- Complete file inventory (new and modified files)
- Usage examples
- Multi-client considerations
- Performance and security considerations
- Future enhancements
- Testing strategy

**Best for:** Understanding the complete system architecture and design decisions

### [remote-file-source-diagrams.md](./remote-file-source-diagrams.md)
**Visual diagrams** - Mermaid diagrams for visualization including:
- System architecture diagram
- Component class diagram
- Multiple sequence diagrams (connection, execution, resource fetch)
- State diagrams (message stream lifecycle, cache management)
- Data flow diagrams (protobuf messages)
- Activity diagram (complete workflow)
- Component dependencies graph
- Message timing diagram

**Best for:** Visual learners and presentations (renders in GitHub/GitLab/VS Code)

### [remote-file-source-quick-reference.md](./remote-file-source-quick-reference.md)
**Developer quick reference** - Practical guide including:
- Client setup code examples (JavaScript)
- Server extension guide (Java)
- Configuration reference
- Debugging tips and logging
- Common issues and solutions
- Performance tips
- Testing checklist
- Quick troubleshooting guide
- Complete API summary

**Best for:** Developers implementing or integrating with the feature

## Quick Links

### For New Developers
Start here: [remote-file-source.md](./remote-file-source.md) → Overview section

### For Integration
Start here: [remote-file-source-quick-reference.md](./remote-file-source-quick-reference.md)

### For Visual Overview
Start here: [remote-file-source-diagrams.md](./remote-file-source-diagrams.md) → System Architecture

### For Debugging
Start here: [remote-file-source-quick-reference.md](./remote-file-source-quick-reference.md) → Debugging section

## Feature Summary

The Remote File Source feature enables Deephaven web clients to provide Groovy source files to the server for dynamic execution, allowing users to write and test code locally without manually uploading files.

### Key Components

**Server Side:**
- `RemoteFileSourcePlugin` - ObjectType plugin
- `RemoteFileSourceCommandResolver` - Flight command handler
- `RemoteFileSourceMessageStream` - Bidirectional message handler and provider
- `RemoteFileSourceClassLoader` - Custom ClassLoader for remote resources
- `GroovyDeephavenSession` - Integration with Groovy execution engine

**Client Side:**
- `JsRemoteFileSourceService` - JavaScript/GWT client API
- Bidirectional protobuf message stream
- Event-driven resource request handling

**Protocol:**
- Flight commands for plugin fetching
- Bidirectional message stream for resource requests/responses
- Protobuf messages defined in `remotefilesource.proto`

### Basic Usage

```javascript
// Client (JavaScript)
const service = await RemoteFileSourceService.fetchPlugin(connection);
service.addEventListener(EVENT_REQUEST_SOURCE, (event) => {
    const content = readFile(event.detail.getResourceName());
    event.detail.respond(content);
});
await service.setExecutionContext(["com/example/Script.groovy"]);
```

```groovy
// Server (Groovy script) - transparent to script authors
import com.example.Script  // Automatically fetched from client
new Script().run()
```

## File Locations

### Source Code
- **Plugin:** `plugin/remotefilesource/`
- **Engine:** `engine/base/src/main/java/io/deephaven/engine/util/RemoteFileSource*.java`
- **Session:** `engine/table/src/main/java/io/deephaven/engine/util/GroovyDeephavenSession.java`
- **Client:** `web/client-api/src/main/java/io/deephaven/web/client/api/remotefilesource/`
- **Proto:** `proto/proto-backplane-grpc/src/main/proto/deephaven_core/proto/remotefilesource.proto`

### Tests
- **Unit tests:** (TBD - not yet implemented in branch)
- **Integration tests:** (TBD - not yet implemented in branch)

## Contributing

When modifying this feature:

1. **Update documentation:** Keep these docs in sync with code changes
2. **Add tests:** Ensure new functionality has appropriate test coverage
3. **Update diagrams:** Modify Mermaid diagrams if architecture changes
4. **Update quick reference:** Add new API methods or configuration options
5. **Version control:** Update "Last Updated" dates in documents

## Related Issues

- **JIRA:** DH-20578 (Groovy Remote File Sourcing)

## Support

For questions or issues:
1. Check the [Quick Troubleshooting Guide](./remote-file-source-quick-reference.md#quick-troubleshooting-guide)
2. Review [Common Issues](./remote-file-source-quick-reference.md#common-issues)
3. Enable [Debug Logging](./remote-file-source-quick-reference.md#enable-debug-logging-server)
4. Contact the Deephaven team

---

**Branch:** `DH-20578_groovy-remote-file-sourcing`  
**Last Updated:** February 25, 2026

