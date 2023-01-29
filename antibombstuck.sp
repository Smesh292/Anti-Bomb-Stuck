#include <sdktools>
#include <sdkhooks>

#pragma semicolon 1
#pragma newdecls required

#define MAXPLAYER MAXPLAYERS + 1

float g_vec1[MAXPLAYER][3],
        g_vec2[MAXPLAYER][3];

bool g_allowPickC4 = true;

char g_path[PLATFORM_MAX_PATH] = "";

ArrayList g_array = null;

int g_countSpot = 0;

bool g_chatAwaiting[MAXPLAYER] = {false, ...};

public Plugin myinfo =
{
    name = "Anti-Bomb Stuck",
    author = "Niks Jurēvičs (Smesh, Smesh292)",
    description = "Do zone with you can take up bomb if has it in it.",
    version = "1.0",
    url = "http://www.sourcemod.net/"
};

public void OnPluginStart()
{
    Path();

    HookEvent("bomb_planted", OnBombPlanted, EventHookMode_Post);
    HookEvent("round_start", OnRoundStart, EventHookMode_Post);
    HookEvent("bomb_pickup", OnBombPickup, EventHookMode_Post);
    HookEvent("bomb_dropped", OnBombDropped, EventHookMode_Post);

    AddCommandListener(OnTypeNumber, "say");
    AddCommandListener(OnTypeNumber, "say_team");

    RegAdminCmd("sm_setspot", CommandSetSpot, ADMFLAG_CUSTOM1, "Set bomb spot.", "", 0);

    return;
}

public void OnMapStart()
{
    Path();

    return;
}

public void OnClientDisconnect(int client)
{
    g_chatAwaiting[client] = false;

    return;
}

void Path()
{
    char buffer[192] = "";
    BuildPath(Path_SM, g_path, sizeof(g_path), "data/trueexpert/");

    if(DirExists(g_path, false, "GAME") == false)
    {
        CreateDirectory(g_path, 511, false, "DEFAULT_WRITE_PATH");
    }

    BuildPath(Path_SM, g_path, sizeof(g_path), "data/trueexpert/bombspot/");

    if(DirExists(g_path, false, "GAME") == false)
    {
        CreateDirectory(g_path, 511, false, "DEFAULT_WRITE_PATH");
    }

    GetCurrentMap(buffer, sizeof(buffer));
    BuildPath(Path_SM, g_path, sizeof(g_path), "data/trueexpert/bombspot/bomb-%s.txt", buffer);

    return;
}

void OnBombPlanted(Event event, const char[] name, bool dontBroadcast)
{
    g_allowPickC4 = false;

    return;
}

void OnBombPickup(Event event, const char[] name, bool dontBroadcast)
{
    g_allowPickC4 = false;

    return;
}

void OnBombDropped(Event event, const char[] name, bool dontBroadcast)
{
    g_allowPickC4 = true;

    return;
}

void OnRoundStart(Event event, const char[] name, bool dontBroadcast)
{
    g_allowPickC4 = true;
    g_countSpot = 0;

    delete g_array;
    g_array = new ArrayList(256);

    KeyValues kv = new KeyValues("Bomb", "", "");

    if(kv.ImportFromFile(g_path) == true && kv.GotoFirstSubKey(true) == true)
    {
        char section[16] = "";
        float vec1[3] = {0.0, ...}, vec2[3] = {0.0, ...}, defvalue[3] = {0.0, ...};

        do
        {
            if(kv.GetSectionName(section, sizeof(section)) == true)
            {
                kv.GetVector("origin1", vec1, defvalue);
                kv.GetVector("origin2", vec2, defvalue);

                CreateZone(section, vec1, vec2);
            }

            continue;
        }

        while(kv.GotoNextKey(true) == true);
    }

    return;
}

void CreateZone(char[] section, float vec1[3], float vec2[3])
{
    char trigger[32] = "";
    Format(trigger, sizeof(trigger), "trueexpert-c4-%s", section);

    int entity = CreateEntityByName("trigger_multiple", -1);

    DispatchKeyValue(entity, "spawnflags", "1"); //https://github.com/shavitush/bhoptimer
    DispatchKeyValue(entity, "wait", "0");
    DispatchKeyValue(entity, "targetname", trigger);

    DispatchSpawn(entity);

    SetEntityModel(entity, "models/player/t_arctic.mdl");

    float center[3] = {0.0, ...};

    //https://stackoverflow.com/questions/4355894/how-to-get-center-of-set-of-points-using-python
    for(int i = 0; i <= 2; i++)
    {
        center[i] = (vec1[i] + vec2[i]) / 2.0;

        continue;
    }

    float value = (vec1[2] - vec2[2]) / 2.0;
    center[2] -= FloatAbs(value);

    TeleportEntity(entity, center, NULL_VECTOR, NULL_VECTOR); //Thanks to https://amx-x.ru/viewtopic.php?f=14&t=15098 http://world-source.ru/forum/102-3743-1

    float mins[3] = {0.0, ...};
    float maxs[3] = {0.0, ...};

    for(int i = 0; i <= 2; i++)
    {
        mins[i] = (vec1[i] - vec2[i]) / 2.0;

        if(mins[i] > 0.0)
        {
            mins[i] *= -1.0;
        }

        maxs[i] = (vec1[i] - vec2[i]) / 2.0;

        if(maxs[i] < 0.0)
        {
            maxs[i] *= -1.0;
        }

        continue;
    }

    SetEntPropVector(entity, Prop_Send, "m_vecMins", mins, 0); //https://forums.alliedmods.net/archive/index.php/t-301101.html
    SetEntPropVector(entity, Prop_Send, "m_vecMaxs", maxs, 0);

    SetEntProp(entity, Prop_Send, "m_nSolidType", 2, 4, 0);

    SDKHook(entity, SDKHook_StartTouchPost, OnZoneStartTouch);

    char buffer[256] = "";
    Format(buffer, sizeof(buffer), "%f,%f,%f,%f,%f,%f", vec1[0], vec1[1], vec1[2], vec2[0], vec2[1], vec2[2]);
    g_array.PushString(buffer);

    g_countSpot++;

    return;
}

void OnZoneStartTouch(int entity, int other)
{
    if(!(0 < other <= MaxClients))
    {
        return;
    }

    if(g_allowPickC4 == false)
    {
        return;
    }

    int c4 = INVALID_ENT_REFERENCE;
    float vec[3] = {0.0, ...}, nulled[3] = {0.0, ...}, vec1[3] = {0.0, ...}, vec2[3] = {0.0, ...}, vecBomb[3] = {0.0, ...};
    char trigger[32] = "", buffer[128] = "", buffers[6][16];

    GetClientAbsOrigin(other, vec);

    GetEntPropString(entity, Prop_Data, "m_iName", trigger, sizeof(trigger), 0);
    ExplodeString(trigger, "-", buffers, 4, 16, false);

    int area = StringToInt(buffers[2], 10);

    while((c4 = FindEntityByClassname(c4, "weapon_c4")) != INVALID_ENT_REFERENCE)
    {
        GetEntPropVector(c4, Prop_Data, "m_vecAbsOrigin", vecBomb);

        for(int i = 1; i <= g_countSpot; i++)
        {
            if(area != i)
            {
                continue;
            }

            g_array.GetString(i - 1, buffer, sizeof(buffer));
            ExplodeString(buffer, ",", buffers, 6, 16, false);
            
            vec1[0] = StringToFloat(buffers[0]);
            vec1[1] = StringToFloat(buffers[1]);
            vec1[2] = StringToFloat(buffers[2]);
            vec2[0] = StringToFloat(buffers[3]);
            vec2[1] = StringToFloat(buffers[4]);
            vec2[2] = StringToFloat(buffers[5]);

            //d = ((x2 - x1)2 + (y2 - y1)2 + (z2 - z1)2)1/2 //https://www.engineeringtoolbox.com/distance-relationship-between-two-points-d_1854.html and do center of trigger
            float distance = Pow(Pow(vecBomb[0] - ((vec1[0] + vec2[0]) / 2.0), 2.0) + Pow(vecBomb[1] - ((vec1[1] + vec2[1]) / 2.0), 2.0) + Pow(vecBomb[2] - ((vec1[2] + vec2[2]) / 2.0), 2.0), 0.5);

            //PrintToServer("%f", distance);

            //if((((vec1[0] < 0.0 && vec1[0] >= vecBomb[0]) || (vec1[0] > 0.0 && vec1[0] <= vecBomb[0])) && ((vec1[1] < 0.0 && vec1[1] <= vecBomb[1]) || (vec1[1] > 0.0 && vec1[1] >= vecBomb[1])) && ((vec1[2] > 0.0 && vec1[2] <= vecBomb[2]) || (vec1[2] < 0.0 && vec1[2] >= vecBomb[2]))) &&
            //    (((vec2[0] < 0.0 && vec2[0] <= vecBomb[0]) || (vec2[0] > 0.0 && vec2[0] >= vecBomb[0])) && ((vec2[1] < 0.0 && vec2[1] >= vecBomb[1]) || (vec2[1] > 0.0 && vec2[1] <= vecBomb[1])) && ((vec2[2] > 0.0 && vec2[2] >= vecBomb[2]) || (vec2[2] < 0.0 && vec2[2] <= vecBomb[2]))))
            
            if(distance < 300.0)
            {
                TeleportEntity(c4, vec, NULL_VECTOR, nulled);
            }
        }

        break;
    }

    return;
}

Action CommandSetSpot(int client, int args)
{
    char buffer[16] = "";
    GetCmdArgString(buffer, sizeof(buffer));

    if(strlen(buffer) == 0)
    {
        Menu menu = new Menu(MenuHandler, MENU_ACTIONS_DEFAULT);
        menu.SetTitle("Set spot for bomb?");
        menu.AddItem("go", "GO!");
        menu.Display(client, 60);
    }

    else if(strlen(buffer) > 0)
    {
        if(StrEqual(buffer, "1", true) == true)
        {
            GetClientAbsOrigin(client, g_vec1[client]);
            g_vec1[client][2] -= 128.0;
        }

        else if(StrEqual(buffer, "2", true) == true)
        {
            GetClientAbsOrigin(client, g_vec2[client]);
            g_vec2[client][2] += 128.0;
        }

        else if(StrEqual(buffer, "done", true) == true)
        {
            g_chatAwaiting[client] = true;

            PrintToChat(client, "Type spot number in chat (1 - ...)");
        }
    }

    return Plugin_Handled;
}

int MenuHandler(Menu menu, MenuAction action, int param1, int param2)
{
    switch(action)
    {
        case MenuAction_Select:
        {
            switch(param2)
            {
                case 0:
                {
                    GetClientAbsOrigin(param1, g_vec1[param1]);

                    Menu menu2 = new Menu(MenuHandler2, MENU_ACTIONS_DEFAULT);
                    menu2.SetTitle("Set first point here?");
                    menu2.AddItem("yes", "Yes");
                    menu2.Display(param1, 60);
                }
            }
        }

        case MenuAction_End:
        {
            delete menu;
        }
    }

    return view_as<int>(action);
}

int MenuHandler2(Menu menu, MenuAction action, int param1, int param2)
{
    switch(action)
    {
        case MenuAction_Select:
        {
            switch(param2)
            {
                case 0:
                {
                    GetClientAbsOrigin(param1, g_vec2[param1]);
                    g_vec2[param1][2] += 128.0;

                    Menu menu2 = new Menu(MenuHandler3, MENU_ACTIONS_DEFAULT);
                    menu2.SetTitle("Set second point here?");
                    menu2.AddItem("yes", "Yes");
                    menu2.Display(param1, 60);
                }
            }
        }

        case MenuAction_End:
        {
            delete menu;
        }
    }

    return view_as<int>(action);
}

int MenuHandler3(Menu menu, MenuAction action, int param1, int param2)
{
    switch(action)
    {
        case MenuAction_Select:
        {
            switch(param2)
            {
                case 0:
                {
                    g_chatAwaiting[param1] = true;

                    PrintToChat(param1, "Type spot number in chat (1 - ...)");
                }
            }
        }

        case MenuAction_End:
        {
            delete menu;
        }
    }

    return view_as<int>(action);
}

Action OnTypeNumber(int client, const char[] command, int argc)
{
    if(g_chatAwaiting[client] == true)
    {
        char buffer[16] = "";
        GetCmdArgString(buffer, sizeof(buffer));

        ReplaceString(buffer, sizeof(buffer), "\"", "", true); //somehow working here

        int num = StringToInt(buffer, 10);

        if(num > 0)
        {
            KeyValues kv = new KeyValues("Bomb", "", "");
            kv.ImportFromFile(g_path);
            kv.JumpToKey(buffer, true);
            kv.SetVector("origin1", g_vec1[client]);
            kv.SetVector("origin2", g_vec2[client]);
            kv.Rewind();
            kv.ExportToFile(g_path);
            delete kv;
        }

        g_chatAwaiting[client] = false;

        return Plugin_Handled;
    }

    return Plugin_Continue;
}
