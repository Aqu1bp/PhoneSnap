namespace PhoneSnap.Core.Receiver;

public enum ReceiverActivity
{
    Stopped,
    Starting,
    Ready,
    Failed,
}

public sealed record ReceiverState(ReceiverActivity Activity, string? Error = null)
{
    public static ReceiverState Stopped { get; } = new(ReceiverActivity.Stopped);
}

public sealed class ReceiverStateChangedEventArgs : EventArgs
{
    public ReceiverStateChangedEventArgs(ReceiverState state)
    {
        State = state ?? throw new ArgumentNullException(nameof(state));
    }

    public ReceiverState State { get; }
}
