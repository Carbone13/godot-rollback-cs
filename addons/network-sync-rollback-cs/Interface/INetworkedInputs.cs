using Godot.Collections;

public interface INetworkedInputs
{
    Dictionary<int, string> GetLocalInput ();
    Dictionary<int, string> PredictRemoteInput (Dictionary<int, string> previousInput, int ticksSinceRealInput);
}
