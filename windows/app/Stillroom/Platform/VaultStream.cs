using System.Buffers;
using System.Runtime.InteropServices.WindowsRuntime;
using System.Security.Cryptography;
using Stillroom.Native;
using Windows.Foundation;
using Windows.Storage.Streams;

namespace Stillroom.Platform;

/// <summary>A sealed file as a stream for Windows' media player (the Mac's `VaultStreamLoader`): each read the player
/// asks for is opened from the sealed chunks as it's asked for, through the engine's reader. Nothing unsealed is ever
/// written to disk, and only what's being played is in memory. Read only.</summary>
internal sealed class VaultStream : IRandomAccessStream
{
    /// <summary>The engine's reader, shared by this stream and its clones, closed when the last of them is.</summary>
    private sealed class Shared(Reader reader)
    {
        public readonly Reader Reader = reader;
        public int Users = 1;
        public bool Closed;
    }

    private readonly Shared shared;
    private bool disposed;

    public VaultStream(Reader reader) : this(new Shared(reader)) { }

    private VaultStream(Shared shared) => this.shared = shared;

    public ulong Size
    {
        get => shared.Reader.Size;
        set => throw new NotSupportedException("A sealed file is read only.");
    }

    public ulong Position { get; private set; }
    public bool CanRead => true;
    public bool CanWrite => false;

    public void Seek(ulong position) => Position = position;

    public IRandomAccessStream CloneStream()
    {
        lock (shared)
        {
            ObjectDisposedException.ThrowIf(shared.Closed, this);
            shared.Users++;
            return new VaultStream(shared);
        }
    }

    public IInputStream GetInputStreamAt(ulong position)
    {
        var clone = (VaultStream)CloneStream();
        clone.Position = position;
        return clone;
    }

    public IOutputStream GetOutputStreamAt(ulong position) => throw new NotSupportedException("A sealed file is read only.");

    /// <summary>Up to `count` bytes from where the stream is, into `buffer`, off the UI thread. The pieces read are
    /// wiped once copied out.</summary>
    public IAsyncOperationWithProgress<IBuffer, uint> ReadAsync(IBuffer buffer, uint count, InputStreamOptions options) =>
        AsyncInfo.Run<IBuffer, uint>((cancel, _) => Task.Run(() =>
        {
            var wanted = (int)Math.Min(count, buffer.Capacity);
            var piece = ArrayPool<byte>.Shared.Rent(Math.Max(wanted, 1));
            try
            {
                int read;
                // The lock makes closing wait for a read under way: the engine's reader is never freed under one.
                lock (shared)
                {
                    if (shared.Closed || disposed) throw new ObjectDisposedException(nameof(VaultStream));
                    read = shared.Reader.Read(Position, piece.AsSpan(0, wanted));
                }
                piece.CopyTo(0, buffer, 0, read);
                buffer.Length = (uint)read;
                Position += (ulong)read;
                return buffer;
            }
            finally
            {
                CryptographicOperations.ZeroMemory(piece);
                ArrayPool<byte>.Shared.Return(piece);
            }
        }, cancel));

    public IAsyncOperationWithProgress<uint, uint> WriteAsync(IBuffer buffer) => throw new NotSupportedException("A sealed file is read only.");

    public IAsyncOperation<bool> FlushAsync() => AsyncInfo.Run(_ => Task.FromResult(true));

    /// <summary>The engine's reader (and the item key in it) let go of now, for this stream and every copy the player
    /// made of it, whatever it still holds: the card closed, or the vault locked. Reads after it fail.</summary>
    public void CloseAll()
    {
        lock (shared)
        {
            if (shared.Closed) return;
            shared.Closed = true;
            shared.Reader.Dispose();
        }
    }

    public void Dispose()
    {
        lock (shared)
        {
            if (disposed) return;
            disposed = true;
            if (--shared.Users > 0 || shared.Closed) return;
            shared.Closed = true;
            shared.Reader.Dispose();
        }
    }
}
