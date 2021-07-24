using Godot;
using System;

public abstract class NetworkAdaptor : Node
{
    [Signal] public delegate void ReceivedInputTick (int peerID, byte[] msg);
    [Signal] public delegate void Pinged (int peerID, byte[] msg);
    [Signal] public delegate void PingedBack (int peerID, byte[] msg);
    
    public abstract void Attach (SyncManager manager);
    public abstract void Detach (SyncManager manager);
    public abstract void Start (SyncManager manager);
    public abstract void Stop (SyncManager manager);
    public abstract void SendInputTick (int peerID, byte[] msg);
    public abstract void PingPeer (int peerID, byte[] pingInformations);
    public abstract void PingBackPeer (int peerID, byte[] pingInformations);
    public abstract void Poll ();
}
