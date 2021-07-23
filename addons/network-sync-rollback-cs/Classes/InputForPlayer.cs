using Godot;
using Godot.Collections;

public class InputForPlayer : Reference
{
    public Dictionary<string, Dictionary<int, string>> Input;
    public bool Predicted;

    public InputForPlayer (Dictionary<string, Dictionary<int, string>> _input, bool _predicted)
    {
        Input = _input;
        Predicted = _predicted;
    }
}