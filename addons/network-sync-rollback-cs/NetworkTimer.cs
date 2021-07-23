using Godot;
using Godot.Collections;

public class NetworkTimer : Node, INetworkable
{
    [Export] private bool autostart;
    [Export] private bool oneShot;
    [Export] private int waitTicks;
    [Export] private bool timeoutWithIncompleteInputs = true;

    private int tickLeft;

    private bool running = false;

    [Signal] public delegate void Timeout ();

    public override void _Ready ()
    {
        SyncManager.singleton.Connect(nameof(SyncManager.SyncStopped), this, nameof(OnSyncManagerSyncStopped));
        if (autostart)
            Start();
    }

    public bool IsStopped () => !running;

    public void Start (int ticks = -1)
    {
        if (ticks > 0)
            waitTicks = ticks;
        tickLeft = waitTicks;
        running = true;
    }

    public void Stop ()
    {
        running = false;
        tickLeft = 0;
    }

    public void OnSyncManagerSyncStopped ()
    {
        Stop();
    }

    public Dictionary<string, string> SaveState ()
    {
        return new Dictionary<string, string>
        {
            {"running", running ? "1" : "0"},
            {"wait_ticks", waitTicks.ToString()},
            {"ticks_left", tickLeft.ToString()}
        };
    }

    public void LoadState (Dictionary<string, string> state)
    {
        running = int.Parse(state["running"]) == 1;
        waitTicks = int.Parse(state["wait_ticks"]);
        tickLeft = int.Parse(state["ticks_left"]);
    }

    public void InterpolateState (Dictionary<string, string> oldState, Dictionary<string, string> newState, float weight)
    {
        
    }

    public void NetworkTick (float delta, Dictionary<int, string> input)
    {
        if (!running) return;
        if (tickLeft <= 0)
        {
            running = false;
            return;
        }

        tickLeft -= 1;

        if (tickLeft == 0)
        {
            if (!oneShot)
            {
                tickLeft = waitTicks;
            }

            if (timeoutWithIncompleteInputs || SyncManager.singleton.IsCurrentPlayerInputComplete())
            {
                EmitSignal(nameof(Timeout));
            }
        }
    }
}
