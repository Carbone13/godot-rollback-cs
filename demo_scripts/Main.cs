using Godot;
using System;
using System.ComponentModel;
using System.Linq;

public class Main : Node2D
{
    public Control ConnectionPanel;
    public Label MessageLabel;
    
    public const int SERVER_PORT = 3456;

    public override void _Ready ()
    {
        ConnectionPanel = GetNode<Control>("CanvasLayer/ConnectionPanel");
        MessageLabel = GetNode<Label>("CanvasLayer/MessageLabel");
        
        GetTree().Connect("network_peer_connected", this, nameof(OnNetworkPeerConnected));
        GetTree().Connect("network_peer_disconnected", this, nameof(OnNetworkPeerDisconnected));
        GetTree().Connect("server_disconnected", this, nameof(OnServerDisconnected));
        SyncManager.singleton.Connect(nameof(SyncManager.SyncStarted), this, nameof(OnSyncManagerSyncStarted));
        SyncManager.singleton.Connect(nameof(SyncManager.SyncLost), this, nameof(OnSyncManagerSyncLost));
        SyncManager.singleton.Connect(nameof(SyncManager.SyncRegained), this, nameof(OnSyncManagerSyncRegained));
        SyncManager.singleton.Connect(nameof(SyncManager.SyncError), this, nameof(OnSyncManagerSyncError));

        var cmdlineArgs = OS.GetCmdlineArgs();
        if(cmdlineArgs.Contains("server"))
            _on_ServerButton_pressed();
        else if (cmdlineArgs.Contains("client"))
            _on_ClientButton1_pressed();

    }

    public void _on_ServerButton_pressed ()
    {
        var peer = new NetworkedMultiplayerENet();
        peer.CreateServer(SERVER_PORT, 2);
        
        UPNP upnp = new UPNP();
        //upnp.Discover();
        //upnp.AddPortMapping(SERVER_PORT);
        
        GetTree().NetworkPeer = peer;
        ConnectionPanel.Visible = false;
    }

    public void _on_ClientButton1_pressed ()
    {
        var peer = new NetworkedMultiplayerENet();
        peer.CreateClient(GetNode<LineEdit>("CanvasLayer/ConnectionPanel/Address").Text, SERVER_PORT);
        GetTree().NetworkPeer = peer;
        ConnectionPanel.Visible = false;
        MessageLabel.Text = "Connecting...";
    }

    public async void OnNetworkPeerConnected (int peerID)
    {
        GD.Print("peer " + peerID + " connected");
        
        GetNode("ServerPlayer").SetNetworkMaster(1);
        if (GetTree().IsNetworkServer())
        {
            GetNode("ClientPlayer").SetNetworkMaster(peerID);
        }
        else
        {
            GetNode("ClientPlayer").SetNetworkMaster(GetTree().GetNetworkUniqueId());
        }
        
        SyncManager.singleton.AddPeer(peerID);

        if (GetTree().IsNetworkServer())
        {
            MessageLabel.Text = "Starting...";
            await ToSignal(GetTree().CreateTimer(2.0f), "timeout");
            SyncManager.singleton.Start();
        }
    }
    
    public void OnNetworkPeerDisconnected (int peerID)
    {
        
        MessageLabel.Text = "Disconnected";
        SyncManager.singleton.RemovePeer(peerID);
    }
    
    public void OnServerDisconnected ()
    {
        OnNetworkPeerDisconnected(1);
    }
    
    public void OnSyncManagerSyncStarted ()
    {
        MessageLabel.Text = "Started !";
    }
    
    public void OnSyncManagerSyncLost ()
    {
        MessageLabel.Text = "Re-syncing...";
    }
    
    public void OnSyncManagerSyncRegained ()
    {
        MessageLabel.Text = "";
    }
    
    public void OnSyncManagerSyncError (string msg)
    {
        MessageLabel.Text = "Fatal sync error: " + msg;
        var peer = GetTree().NetworkPeer;
        if (peer != null)
        {
            
        }
        SyncManager.singleton.ClearPeers();
    }
}
