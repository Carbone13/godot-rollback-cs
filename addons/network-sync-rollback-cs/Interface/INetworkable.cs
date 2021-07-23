using Godot.Collections;

public interface INetworkable
{
    Dictionary<string, string> SaveState ();
    void LoadState (Dictionary<string, string> state);
    void InterpolateState (Dictionary<string, string> oldState, Dictionary<string, string> newState, float weight);
    
    void NetworkTick (float delta, Dictionary<int, string> input);
}
