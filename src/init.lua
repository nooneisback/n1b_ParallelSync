--!nolint 
--[[
	ParallelSync v2 by nooneisback
	A module that automates modulescript-actor interaction by either blocking
	require from different actors, or syncing values and function calls through
	bindables 

	BlockModule:
		Blocks parallel usage of this module from multiple actors.
		API:
			(ModuleScript:ModuleScript)->(true)
		Usage example:
			luau:
				require(path.to.ParallelSync).BlockModule(script);
				return module;
			roblox-ts:
				import { BlockModule } from ".../ParallelSync";
				...
				BlockModule(script);

	SyncModule:
		Automatically syncs data between multiple actors, essentially allowing a module
		script to be used almost like you would without actors. Limits include all limits that apply
		to bindable functions.
		You can also specify a replacement value to be used by secondary actors by adding _psync
		at the end of its name.
		API:
			(
				ModuleScript:ModuleScript,
				ModuleReturn:{[string]:any}, -- the table returned by the module. This is needed to bypass recursive requires
				DefaultModifier, -- the default behavior used when none is specified in table below
				Modifiers: { [Index:string]:
					"Block" |	-- prevents this value from being accessed outside main thread
					"Sync" |	-- used bindable functions to communicate with the main thread
					"Safe"		-- don't sync and use value as is
				}
			) -> boolean -- true if primary thread, false if secondary
		Usage example:
			luau:
				require(path.to.ParallelSync).SyncModule(script, module, "Block", {
					-- define specific modifiers here
				});
				return module;
			roblox-ts:
				import { SyncModule } from ".../ParallelSync";
				...
				// Tricks roblox-ts into not complaining either about missing or reserved "exports" variable
				declare const exports = "";
				SyncModule(script, exports, "Block", {
					// define specific modifiers here
				});

]]

local _export = {};

-- Blocks any subequent requires
function _export.BlockModule(ModuleScript:ModuleScript)
	if (ModuleScript:GetAttribute("psync_Blocked")) then
		error("This ModuleScript cannot be required in parallel: "..ModuleScript:GetFullName());
	end
	ModuleScript:SetAttribute("psync_Blocked", true);
	ModuleScript:SetAttribute("psync_Synced", true);
	return true;
end

export type ParallelAccessModifier = 
	"Block" |	-- prevents this value/function from being accessed
	"Sync"	|	-- syncs this value using bindables
	"Safe"		-- returns the value/function stored in current thread without syncing
function _export.SyncModule(
	ModuleScript:ModuleScript,				-- the modulescript to sync
	ModuleReturn:any,						-- value returned by the modulescript to avoid recursive require error		
	DefaultModifier:ParallelAccessModifier,	-- the default value to use if none specified in Modifiers table [def:Block]
	Modifiers:{[string]:ParallelAccessModifier}-- value/function name: Modifier
) : boolean -- true if primary thread, otherwise false
	task.synchronize(); -- will spam warnings, but required not to cause a massive mess
	if (ModuleScript:GetAttribute("psync_Blocked")) then
		error("This ModuleScript cannot be required in parallel: "..ModuleScript:GetFullName());
	end
	-- Defaults and overloads
	if (not DefaultModifier) then
		DefaultModifier = "Block";
		Modifiers = {};
	elseif (not Modifiers) then
		if (type(DefaultModifier)=="string") then
			Modifiers = {};
		elseif (type(DefaultModifier)=="table") then
			Modifiers = DefaultModifier;
			DefaultModifier = "Block";
		else
			error("Unexpected type "..type(DefaultModifier))
		end
	end
	local _req = ModuleReturn;
	if (ModuleScript:GetAttribute("psync_Synced") ~= true) then
		-- Is primary
		ModuleScript:SetAttribute("psync_Synced", true);
		local bindGet = Instance.new("BindableFunction"); bindGet.Name = "_psync_get"; bindGet.Parent = ModuleScript;
		local bindSet = Instance.new("BindableFunction"); bindSet.Name = "_psync_set"; bindSet.Parent = ModuleScript;
		local bindCal = Instance.new("BindableFunction"); bindCal.Name = "_psync_cal"; bindCal.Parent = ModuleScript;
		bindGet.OnInvoke = function(i) return _req[i]; end
		bindSet.OnInvoke = function(i,v) _req[i] = v; end
		bindCal.OnInvoke = function(ismethod, i, ...)
			if (ismethod) then
				return _req[i](_req, ...);
			else
				return _req[i](...);
			end
		end
		return true;
	else
		-- Is secondary
		local bindGet = ModuleScript:FindFirstChild("_psync_get");
		local bindSet = ModuleScript:FindFirstChild("_psync_set");
		local bindCal = ModuleScript:FindFirstChild("_psync_cal");
		local _mirr = table.clone(_req);
		table.clear(_req);
		for i,v in pairs(_mirr) do
			local mode = Modifiers[i] or DefaultModifier;
			local psyncalt = _mirr[i.."_psync"];
			if (string.sub(i, #i-6)=="_psync") then
				continue;
			elseif (psyncalt) then
				_mirr[i] = psyncalt;
				Modifiers[i] = "Safe";
			elseif (mode=="Block" or mode=="Safe") then
				continue;
			else
				if (type(v)=="function") then
					Modifiers[i] = "Safe";
					_mirr[i] = function(a,...)
						if (a==_req) then
							bindCal:Invoke(true, i, ...);
						else
							bindCal:Invoke(false, i, a, ...);
						end
					end
				end
			end
		end
		local _meta = setmetatable(_req, {
			__index = function(_, i)
				local mode = Modifiers[i] or DefaultModifier;
				if (mode=="Safe") then
					return _mirr[i];
				elseif (mode=="Block") then
					error(`Value {i} cannot be accessed in parallel`);
				elseif (mode=="Sync") then
					return bindGet:Invoke(i);
				else
					error("Unknown access modifier "..mode);
				end
			end,
			__newindex = function(_, i, v)
				local mode = Modifiers[i] or DefaultModifier;
				if (mode=="Safe") then
					_mirr[i] = v;
				elseif (mode=="Block") then
					error(`Value {i} cannot be accessed in parallel`);
				elseif (mode=="Sync") then
					bindSet:Invoke(i, v);
				else
					error("Unknown access modifier "..mode);
				end
			end
		});
		return false;
	end
end

return _export;