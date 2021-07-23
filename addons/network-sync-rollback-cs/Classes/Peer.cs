using System.Collections.Generic;
using Godot;

public class Peer : Reference
{
    public int PeerID;
    
    public ulong RTT;
    public ulong LastPingReceived;
    public long DeltaTime;
    
    public int LastRemoteTickReceived = 0;
    public int NextLocalTickRequested = 1;
    
    public int RemoteLag;
    public int LocalLag;
    
    public float CalculatedAdvantage;
    public readonly List<int> AdvantageList = new List<int>();

    public Peer (int _peerId)
    {
        PeerID = _peerId;
    }

    public void RecordAdvantage (int ticksToCalculateAdvantage)
    {
        AdvantageList.Add(LocalLag - RemoteLag);

        if (AdvantageList.Count >= ticksToCalculateAdvantage)
        {
            float total = 0;

            foreach (int advantage in AdvantageList)
                total += advantage;
            CalculatedAdvantage = total / AdvantageList.Count;
            AdvantageList.Clear();
        }
    }

    public void ClearAdvantage ()
    {
        CalculatedAdvantage = 0.0f;
        AdvantageList.Clear();
    }

    public void Clear ()
    {
        RTT = 0;
        LastPingReceived = 0;
        DeltaTime = 0;
        LastRemoteTickReceived = 0;
        NextLocalTickRequested = 0;
        RemoteLag = 0;
        LocalLag = 0;
        ClearAdvantage();
    }
}