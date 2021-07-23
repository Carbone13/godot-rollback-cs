using Godot;
using System;

public class RPCNetworkAdaptor : NetworkAdaptor
{
    public override void Attach (SyncManager manager)
    {
        
    }

    public override void Detach (SyncManager manager)
    {
        
    }

    public override void Start (SyncManager manager)
    {
        
    }

    public override void Stop (SyncManager manager)
    {
        
    }

    public override void SendInputTick (int peerID, byte[] msg)
    {
        RpcUnreliableId(peerID, nameof(RIT), msg);
    }

    public override void Poll ()
    {
        
    }

    [Remote]
    public void RIT (byte[] msg)
    {
        EmitSignal(nameof(ReceivedInputTick), GetTree().GetRpcSenderId(), msg);
    }
}
