using Godot;
using Godot.Collections;

public class SpawnManager : Node, INetworkable
{
    public static SpawnManager singleton;
    [Signal]
    public delegate void SceneSpawned (string signalName, Node spawnedNode, PackedScene scene, Dictionary data);
    
    private Dictionary<string, Dictionary> spawnRecords = new Dictionary<string, Dictionary>();
    private Dictionary<string, Node> spawnedNodes = new Dictionary<string, Node>();
    private Dictionary<string, int> counter = new Dictionary<string, int>();
    
    public override void _Ready ()
    {
        AddToGroup("network_sync");
        singleton = this;
        SyncManager.singleton.Connect(nameof(SyncManager.SyncStopped), this, nameof(OnSyncManagerSyncStopped));
    }

    public void OnSyncManagerSyncStopped ()
    {
         spawnRecords.Clear();
         spawnedNodes.Clear();
    }

    public string RenameNode (string name)
    {
        if (!counter.ContainsKey(name))
        {
            counter[name] = 0;
        }

        counter[name] += 1;
        return name + counter[name];
    }

    public Node Spawn (string name, Node parent, PackedScene scene, Dictionary data, bool rename = true,
        string signal = "")
    {
        var spawnedNode = scene.Instance();
        if (signal == "")
        {
            signal = name;
        }

        if (rename)
        {
            name = RenameNode(name);
        }

        spawnedNode.Name = name;
        parent.AddChild(spawnedNode);

        if (spawnedNode.HasMethod("NetworkSpawnPreprocess"))
        {
            data = spawnedNode.Call("NetworkSpawnPreprocess", data) as Dictionary;
        }

        if (spawnedNode.HasMethod("NetworkSpawn"))
        {
            spawnedNode.Call("NetworkSpawn");
        }

        Dictionary spawnRecord = new Dictionary
        {
            {"name", spawnedNode.Name},
            {"parent", parent.GetPath().ToString()},
            {"scene", scene.ResourcePath},
            {"data", JSON.Print(data)},
            {"signal_name", signal}
        };

        var nodePath = spawnedNode.GetPath().ToString();
        spawnRecords[nodePath] = spawnRecord;
        spawnedNodes[nodePath] = spawnedNode;

        EmitSignal(nameof(SceneSpawned), signal, spawnedNode, scene, data);
        
        return spawnedNode;
    }

    public Dictionary<string, string> SaveState ()
    {
        foreach (string nodePath in spawnedNodes.Keys)
        {
            var node = spawnedNodes[nodePath];
            if (!IsInstanceValid(node))
            {
                spawnedNodes.Remove(nodePath);
                spawnRecords.Remove(nodePath);
            }
            else if (node.IsQueuedForDeletion())
            {
                if (node.GetParent() != null)
                {
                    node.GetParent().RemoveChild(node);
                }
                spawnedNodes.Remove(nodePath);
                spawnRecords.Remove(nodePath);
            }
        }

        return new Dictionary<string, string>
        {
            {"spawn_records", JSON.Print(spawnRecords)},
            {"counter", JSON.Print(counter)}
        };
    }

    public void LoadState (Dictionary<string, string> state)
    {
        Dictionary readSpawnRecords = JSON.Parse(state["spawn_records"]).Result as Dictionary;
        Dictionary readCounter = JSON.Parse(state["counter"]).Result as Dictionary;
        spawnRecords = new Dictionary<string, Dictionary>(readSpawnRecords.Duplicate());
        counter = new Dictionary<string, int>(readCounter.Duplicate());

        foreach (string nodePath in spawnedNodes.Keys)
        {
            if (!spawnRecords.ContainsKey(nodePath))
            {
                var node = spawnedNodes[nodePath];
                if (node.HasMethod("NetworkDespawn"))
                {
                    node.Call("NetworkDespawn");
                }

                if (node.GetParent() != null)
                {
                    node.GetParent().RemoveChild(node);
                }
                node.QueueFree();
                spawnedNodes.Remove(nodePath);
            }
        }
        
        foreach (string nodePath in spawnedNodes.Keys)
        {
            if (spawnedNodes.ContainsKey(nodePath))
            {
                var oldNode = spawnedNodes[nodePath];
                if (!IsInstanceValid(oldNode) || oldNode.IsQueuedForDeletion())
                {
                    spawnedNodes.Remove(nodePath);
                }
            }

            if (!spawnedNodes.ContainsKey(nodePath))
            {
                var spawnRecord = spawnRecords[nodePath];

                var parent = GetTree().CurrentScene.GetNode(spawnRecord["parent"] as NodePath);
                var scene = ResourceLoader.Load<PackedScene>(spawnRecord["scene"] as string);

                var spawnedNode = scene.Instance();
                spawnedNode.Name = spawnRecord["name"] as string;
                parent.AddChild(spawnedNode);

                if (spawnedNode.HasMethod("NetworkSpawn"))
                {
                    spawnedNode.Call("NetworkSpawn");
                }

                spawnedNodes[nodePath] = spawnedNode;
                EmitSignal(nameof(SceneSpawned), spawnRecord["signal_name"], spawnedNode, scene, JSON.Parse(spawnRecord["data"] as string).Result as Dictionary);
            }
        }
    }

    public void InterpolateState (Dictionary<string, string> oldState, Dictionary<string, string> newState, float weight)
    {
        
    }

    public void NetworkTick (float delta, NodeInputs input)
    {
        
    }
}
