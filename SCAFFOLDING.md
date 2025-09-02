'''
src                                 # Root source directory for the tardy async runtime
├── aio                             # Async I/O abstraction layer for platform-specific async operations
│   ├── apis                        # Platform-specific async I/O API implementations
│   │   ├── epoll.zig               # Linux epoll backend for async I/O (Linux >= 2.5.45)
│   │   ├── io_uring.zig            # Linux io_uring backend for async I/O (Linux >= 5.1)
│   │   ├── kqueue.zig              # BSD/macOS kqueue backend for async I/O
│   │   └── poll.zig                # POSIX poll backend for async I/O (fallback/universal)
│   ├── completion.zig              # Async operation completion result types and handling
│   ├── job.zig                     # Async job management and queueing system
│   └── lib.zig                     # Main async I/O library interface and backend selection
├── channel                         # Inter-task communication primitives
│   └── spsc.zig                    # Single-producer single-consumer lock-free channel
├── core                            # Core data structures and utilities
│   ├── atomic_bitset.zig           # Thread-safe bitset using atomic operations
│   ├── atomic_ring.zig             # Lock-free ring buffer using atomic operations
│   ├── pool.zig                    # Memory pool for efficient allocation/deallocation
│   ├── queue.zig                   # Queue data structure implementation
│   ├── ring.zig                    # Ring buffer implementation
│   └── zero_copy.zig               # Zero-copy buffer management for efficient I/O
├── cross                           # Cross-platform abstractions for OS-specific APIs
│   ├── fd.zig                      # File descriptor abstraction layer
│   ├── lib.zig                     # Main cross-platform library interface
│   └── socket.zig                  # Cross-platform socket abstraction
├── frame                           # Coroutine/stackful frame implementation
│   ├── asm                         # Platform-specific assembly for context switching
│   │   ├── aarch64_gen.asm         # ARM64 context switching assembly
│   │   ├── x86_64_sysv.asm         # x86-64 System V ABI context switching (Linux/BSD/macOS)
│   │   └── x86_64_win.asm          # x86-64 Windows ABI context switching
│   └── lib.zig                     # Frame/coroutine management and scheduling
├── fs                              # Async filesystem operations
│   ├── dir.zig                     # Async directory operations (create, delete, list)
│   ├── file.zig                    # Async file operations (read, write, open, close)
│   └── lib.zig                     # Filesystem library interface and path utilities
├── lib.zig                         # Main tardy library entry point and public API
├── net                             # Async networking operations
│   ├── lib.zig                     # Network library interface
│   └── socket.zig                  # Async socket operations (TCP/UDP, connect, accept, send, recv)
├── runtime                         # Core runtime and task scheduling
│   ├── lib.zig                     # Runtime initialization and management
│   ├── scheduler.zig               # Task scheduler implementation
│   ├── storage.zig                 # Thread-local storage for runtime data
│   ├── task.zig                    # Task abstraction and lifecycle management
│   └── timer.zig                   # Timer and timeout management for async operations
├── stream.zig                      # Stream abstraction for Reader/Writer vtable APIs
└── tests.zig                       # Test utilities and common test infrastructure
'''
