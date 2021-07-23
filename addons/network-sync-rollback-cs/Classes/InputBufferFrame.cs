using System.Collections.Generic;
using Godot;
using Godot.Collections;
using G = Godot.Collections;

public class InputBufferFrame : Reference
{
    public int Tick;
    public G.Dictionary<int, InputForPlayer> Players = new G.Dictionary<int, InputForPlayer>();

    public InputBufferFrame (int _tick)
    {
        Tick = _tick;
    }

    public G.Dictionary<string, G.Dictionary<int, string>> GetPlayerInput (int _peerId)
    {
        if (Players.ContainsKey(_peerId))
            return Players[_peerId].Input;
        return null;
    }

    public bool IsPlayerInputPredicted (int _peerId)
    {
        if (Players.ContainsKey(_peerId))
            return Players[_peerId].Predicted;
        return true;
    }

    public Peer[] GetMissingPeers (G.Dictionary<int, Peer> peers)
    {
        List<Peer> missing = new List<Peer>();
        foreach(Peer peer in peers.Values)
        {
            if(!Players.ContainsKey(peer.PeerID) || Players[peer.PeerID].Predicted)
                missing.Add(peer);
        }

        return missing.ToArray();
    }

    public bool IsComplete (G.Dictionary<int, Peer> peers)
    {
        foreach(Peer peer in peers.Values)
        {
            if (!Players.ContainsKey(peer.PeerID) || Players[peer.PeerID].Predicted)
                return false;
        }

        return true;
    }
}