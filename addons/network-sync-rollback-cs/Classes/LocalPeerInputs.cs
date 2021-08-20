using System;
using System.Collections.Generic;
using System.Text;

/// <summary>
/// Represent the Inputs of all the nodes living in a peer game instance
/// </summary>
public class LocalPeerInputs
{
    /// <summary>
    /// Key is the path of the node
    /// Value is the inputs themselves
    /// </summary>
    public Dictionary<string, NodeInputs> NodeInputsMap = new Dictionary<string, NodeInputs>();
    
    public NodeInputs this[string key]
    {
        get => NodeInputsMap[key];
        set => NodeInputsMap[key] = value;
    }
    
    public byte[] Serialize ()
    {
        var bytes = new List<byte>();

        // Add the dictionary count on the header
        bytes.AddRange(BitConverter.GetBytes(NodeInputsMap.Count));

        foreach (var entry in NodeInputsMap)
        {
            byte[] key = Encoding.ASCII.GetBytes(entry.Key);
            // put the key length, then the key
            bytes.AddRange(BitConverter.GetBytes(key.Length));
            bytes.AddRange(key);
            
            // and then put the NodeInputs
            byte[] _entry = entry.Value.Serialize();
            bytes.AddRange(BitConverter.GetBytes(_entry.Length));
            bytes.AddRange(_entry);
        }
        
        return bytes.ToArray();
    }

    public static LocalPeerInputs Deserialize (byte[] data)
    {
        var toReturn = new LocalPeerInputs();
        int CurrByte = 0;
        
        int elementAmount = BitConverter.ToInt32(data, CurrByte);
        CurrByte+=4;

        for (int i = 0; i < elementAmount; ++i)
        {
            int keyLength = BitConverter.ToInt32(data, CurrByte);
            CurrByte += 4;
            
            string key = Encoding.ASCII.GetString(data, CurrByte, keyLength);
            CurrByte += keyLength;
            
            int valueLength = BitConverter.ToInt32(data, CurrByte);
            CurrByte += 4;
            
            NodeInputs inputs = NodeInputs.Deserialize(data.SubArray(CurrByte, valueLength));
            CurrByte += valueLength;
            
            toReturn[key] = inputs;
        }

        return toReturn;
    }
}

/// <summary>
/// Represent the Inputs for a Node
/// </summary>
public class NodeInputs
{
    /// <summary>
    /// Key is an unique identifier, i.e 1=X Axis, 2=Jump etc...
    /// </summary>
    public Dictionary<int, string> inputs;
    
    public string this[int key]
    {
        get => inputs[key];
        set => inputs.AddOrUpdate(key, value);
    }

    
    public byte[] Serialize ()
    {
        var bytes = new List<byte>();

        // Add the dictionary count on the header
        bytes.AddRange(BitConverter.GetBytes(inputs.Count));

        foreach (var entry in inputs)
        {
            // put the key
            bytes.AddRange(BitConverter.GetBytes(entry.Key));
            
            // serialize the value
            byte[] strEncoded = Encoding.ASCII.GetBytes(entry.Value);
            // add the string length in the section header
            bytes.AddRange(BitConverter.GetBytes(strEncoded.Length));
            bytes.AddRange(strEncoded);
        }
        
        return bytes.ToArray();
    }

    public static NodeInputs Deserialize (byte[] data)
    {
        var toReturn = new NodeInputs();
        int CurrByte = 0;
        
        int elementAmount = BitConverter.ToInt32(data, CurrByte);
        CurrByte += 4;

        for (int i = 0; i<elementAmount; ++i)
        {
            int key = BitConverter.ToInt32(data, CurrByte);
            CurrByte += 4;

            int valueLenght = BitConverter.ToInt32(data, CurrByte);
            CurrByte += 4;

            string value = Encoding.ASCII.GetString(data, CurrByte, valueLenght);
            CurrByte += valueLenght;

            toReturn[key] = value;
        }

        return toReturn;
    }
}