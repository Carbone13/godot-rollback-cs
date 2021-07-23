using Godot;
using System;

public abstract class NetworkAdaptor : Node
{
    [Signal] public delegate void ReceivedInputTick (int peerID, byte[] msg);
    
    public abstract void Attach (SyncManager manager);
    public abstract void Detach (SyncManager manager);
    public abstract void Start (SyncManager manager);
    public abstract void Stop (SyncManager manager);
    public abstract void SendInputTick (int peerID, byte[] msg);
    public abstract void Poll ();
}
