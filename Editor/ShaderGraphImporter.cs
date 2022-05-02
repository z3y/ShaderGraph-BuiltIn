﻿using System;
using System.Collections;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Xml.Linq;
using UnityEditor;
using UnityEngine;
using Directory = UnityEngine.Windows.Directory;

public class ShaderGraphImporter : EditorWindow
{
    [MenuItem("Window/ShaderGraphImporter")]
    static void Init()
    {
        // Get existing open window or if none, make a new one:
        ShaderGraphImporter window = (ShaderGraphImporter)EditorWindow.GetWindow(typeof(ShaderGraphImporter));
        window.Show();
    }

    private static string _shaderCodeEditor = "";
    private static string _customEditor = " ";
    
    
    void OnGUI()
    {
        if (GUILayout.Button("Paste & Import"))
        {
            _shaderCodeEditor = GUIUtility.systemCopyBuffer;
            ImportShader(_shaderCodeEditor);
        }

        _shaderCodeEditor = GUILayout.TextArea(_shaderCodeEditor, GUILayout.Height(200));

        
    }

    private const string ImportPath = "Assets/ShaderGraph/";

    private static readonly string[] FixUnityBug =
    {
        "CustomEditorForRenderPipeline",
        "#pragma multi_compile _ _SCREEN_SPACE_OCCLUSION",
        "#pragma multi_compile _ LIGHTMAP_ON",
        "#pragma multi_compile _ DIRLIGHTMAP_COMBINED",
        "#pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN",
        "#pragma multi_compile _ADDITIONAL_LIGHTS_VERTEX _ADDITIONAL_LIGHTS _ADDITIONAL_OFF",
        "#pragma multi_compile _ _ADDITIONAL_LIGHT_SHADOWS",
        "#pragma multi_compile _ _SHADOWS_SOFT",
        "#pragma multi_compile _ LIGHTMAP_SHADOW_MIXING",
        "#pragma multi_compile _ SHADOWS_SHADOWMASK",
        "#pragma multi_compile _ _MIXED_LIGHTING_SUBTRACTIVE",
        "#pragma multi_compile _ _GBUFFER_NORMALS_OCT",
        "#pragma multi_compile _ _CASTING_PUNCTUAL_LIGHT_SHADOW"
    };

    private static readonly string[] ReplaceCoreRP =
    {
        "#include \"Packages/com.unity.render-pipelines.core/",
        "#include \"Packages/com.z3y.shadergraph-builtin/CoreRP/"
    };

    private static readonly string[] ReplaceShaderGraphLibrary =
    {
        "#include \"Packages/com.unity.shadergraph/",
        "#include \"Packages/com.z3y.shadergraph-builtin/ShaderGraph/"
    };

    private static void ReplaceWithEmpty(ref string[] input, string[] replaceLines)
    {
        foreach (var replaceLine in replaceLines)
        {
            for (var index = 0; index < input.Length; index++)
            {
                var trimmed = input[index].TrimStart();
                if (trimmed.StartsWith(replaceLine, StringComparison.Ordinal))
                {
                    input[index] = string.Empty;
                }
                else if (trimmed.StartsWith(ReplaceCoreRP[0], StringComparison.Ordinal))
                {
                    input[index] = input[index].Replace(ReplaceCoreRP[0], ReplaceCoreRP[1]);
                }
                else if (trimmed.StartsWith(ReplaceShaderGraphLibrary[0], StringComparison.Ordinal))
                {
                    input[index] = input[index].Replace(ReplaceShaderGraphLibrary[0], ReplaceShaderGraphLibrary[1]);
                }

                else if (trimmed.StartsWith("#pragma multi_compile_shadowcaster", StringComparison.Ordinal))
                {
                    input[index] = input[index] + '\n' + "#pragma multi_compile_instancing";
                }

            }
        }
    }

    private static void ImportShader(string shaderCode, string customEditor = " ")
    {
        var fileLines = shaderCode.Split('\n');

        var fileName = fileLines[0].TrimStart().Replace("Shader \"", "").TrimEnd('"').Replace("/", " ");

        fileLines[0] = $"Shader \"Shader Graphs/{fileName}\"";
        
        
       var customEditorIndex = Array.FindIndex(fileLines, x => x.TrimStart().StartsWith("CustomEditor", StringComparison.Ordinal));
       fileLines[customEditorIndex] = customEditor;

       ReplaceWithEmpty(ref fileLines, FixUnityBug);

       if (!Directory.Exists(ImportPath))
       {
           System.IO.Directory.CreateDirectory(ImportPath);
       }
        File.WriteAllLines(ImportPath + fileName + ".shader", fileLines);
        
        AssetDatabase.Refresh();
    }
}