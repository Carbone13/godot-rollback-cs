using Godot;
using Godot.Collections;

public class InputForPlayer : Reference
{
    public LocalPeerInputs Input;
    public bool Predicted;

    public InputForPlayer (LocalPeerInputs _input, bool _predicted)
    {
        Input = _input;
        Predicted = _predicted;
    }
}