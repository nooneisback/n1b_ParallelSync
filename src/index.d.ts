
export function BlockModule(ModuleScript:ModuleScript): true;

export type PsyncModifier = 
	"Block" |	// prevents this value/function from being accessed
	"Sync"	|	// syncs this value using bindables
	"Safe"		// returns the value/function stored in current thread without syncing
export function SyncModule(
	ModuleScript:any,
	ModuleReturn:any,
	DefaultModifier: PsyncModifier,
	Modifiers: Record<string, PsyncModifier>
): boolean;