using Godot;
using Godot.Collections;

public class NetworkAnimationPlayer : AnimationPlayer, INetworkable
{
    public override void _Ready ()
    {
        MethodCallMode = AnimationMethodCallMode.Immediate;
        PlaybackProcessMode = AnimationProcessMode.Manual;
    }

    public Dictionary<string, string> SaveState ()
    {
        if (IsPlaying())
        {
            return new Dictionary<string, string>
            {
                {"is_playing", "1"},
                {"current_animation", CurrentAnimation},
                {"current_position", CurrentAnimationPosition.ToString()}
            };
        }
        else
        {
            return new Dictionary<string, string>
            {
                {"is_playing", "0"},
                {"current_animation", ""},
                {"current_position", "0.0"}
            };
        }
    }

    public void LoadState (Dictionary<string, string> state)
    {
        bool isPlaying = int.Parse(state["is_playing"]) == 1;
        if (isPlaying)
        {
            Play(state["current_animation"]);
            Seek(float.Parse(state["current_position"]), true);
        }
    }

    public void InterpolateState (Dictionary<string, string> oldState, Dictionary<string, string> newState, float weight)
    {
        
    }

    public void NetworkTick (float delta, Dictionary<int, string> input)
    {
        if(IsPlaying())
            Advance(delta);
    }
}
