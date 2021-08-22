using Godot.Collections;

public interface INetworkedInputs
{
    NodeInputs GetLocalInput ();
    NodeInputs PredictRemoteInput (NodeInputs previousInput, int ticksSinceRealInput);
}
