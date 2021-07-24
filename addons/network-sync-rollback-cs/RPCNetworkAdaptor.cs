using Godot;
using System;

public class RPCNetworkAdaptor : NetworkAdaptor
{
    public override void Poll () { }
    public override void Attach (SyncManager manager) { }
    public override void Detach (SyncManager manager) { }
    public override void Start (SyncManager manager) { }
    public override void Stop (SyncManager manager) { }

    public override void SendInputTick (int peerID, byte[] msg)
    {
        RpcUnreliableId(peerID, nameof(RIT), msg);
    }

    public override void PingPeer (int peerID, byte[] pingInformations)
    {
        RpcId(peerID, nameof(Ping), pingInformations);
    }

    public override void PingBackPeer (int peerID, byte[] pingInformations)
    {
        RpcId(peerID, nameof(PingBack), pingInformations);
    }
    
    [Remote]
    public void RIT (byte[] msg)
    {
        EmitSignal(nameof(ReceivedInputTick), GetTree().GetRpcSenderId(), msg);
    }

    [Remote]
    public void Ping (byte[] msg)
    {
        EmitSignal(nameof(Pinged), GetTree().GetRpcSenderId(), msg);
    }
    
    [Remote]
    public void PingBack (byte[] msg)
    {
        EmitSignal(nameof(PingedBack), GetTree().GetRpcSenderId(), msg);
    }
}
