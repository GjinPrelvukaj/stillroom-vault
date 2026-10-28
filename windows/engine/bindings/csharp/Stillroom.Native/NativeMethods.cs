// The engine's C functions (include/stillroom.h), declared for .NET. Use them through Store and Vault (Stillroom.cs),
// which free what the engine gives and turn failures into exceptions.

using System.Runtime.InteropServices;

namespace Stillroom.Native;

/// <summary>Bytes the engine hands out; freed and wiped with stillroom_bytes_free.</summary>
[StructLayout(LayoutKind.Sequential)]
public struct StillroomBytes
{
    public IntPtr Data;
    public nuint Length;
}

internal static unsafe partial class NativeMethods
{
    private const string Library = "stillroom_core";

    [LibraryImport(Library)] internal static partial IntPtr stillroom_last_error();
    [LibraryImport(Library)] internal static partial uint stillroom_abi_version();
    [LibraryImport(Library)] internal static partial void stillroom_string_free(IntPtr value);
    [LibraryImport(Library)] internal static partial void stillroom_bytes_free(StillroomBytes value);
    [LibraryImport(Library)] [return: MarshalAs(UnmanagedType.U1)] internal static partial bool stillroom_keys_are_locked();
    [LibraryImport(Library)] internal static partial int stillroom_exclude_from_crash_reports();
    [LibraryImport(Library)] internal static partial int stillroom_harden_process([MarshalAs(UnmanagedType.U1)] bool blockExtensionDlls, out uint hardened);
    [LibraryImport(Library)] [return: MarshalAs(UnmanagedType.U1)] internal static partial bool stillroom_tpm_available();
    [LibraryImport(Library, StringMarshalling = StringMarshalling.Utf8)] internal static partial int stillroom_protect_folder(string folder);
    [LibraryImport(Library)] internal static partial int stillroom_hello_new_challenge(out StillroomBytes result);
    [LibraryImport(Library, StringMarshalling = StringMarshalling.Utf8)]
    internal static partial int stillroom_secure_prompt(string title, string message, [MarshalAs(UnmanagedType.U1)] bool multiline, out StillroomBytes typed, [MarshalAs(UnmanagedType.U1)] out bool cancelled);

    // Windows' own ways in
    [LibraryImport(Library)] internal static partial int stillroom_store_is_locked_to_a_pc(IntPtr store, [MarshalAs(UnmanagedType.U1)] out bool result);
    [LibraryImport(Library)] internal static partial int stillroom_store_hello_challenge(IntPtr store, out StillroomBytes result);
    [LibraryImport(Library)] internal static partial int stillroom_store_unlock_with_hello(IntPtr store, byte* signature, nuint length, out IntPtr vault);
    [LibraryImport(Library)] internal static partial int stillroom_vault_lock_to_this_pc(VaultHandle vault, out IntPtr recoveryKey);
    [LibraryImport(Library)] internal static partial int stillroom_vault_unlock_from_this_pc(VaultHandle vault);
    [LibraryImport(Library)] internal static partial int stillroom_vault_turn_on_hello(VaultHandle vault, byte* challenge, nuint challengeLength, byte* signature, nuint signatureLength, byte* publicKey, nuint publicKeyLength);
    [LibraryImport(Library)] internal static partial int stillroom_vault_turn_off_hello(VaultHandle vault);

    // Stores
    [LibraryImport(Library, StringMarshalling = StringMarshalling.Utf8)]
    internal static partial int stillroom_store_open(string? root, [MarshalAs(UnmanagedType.U1)] bool readOnly, out IntPtr store);
    [LibraryImport(Library)] internal static partial int stillroom_store_lower_cost_for_tests(IntPtr store);
    [LibraryImport(Library)] internal static partial void stillroom_store_free(IntPtr store);
    [LibraryImport(Library)] internal static partial int stillroom_store_exists(IntPtr store, [MarshalAs(UnmanagedType.U1)] out bool result);
    [LibraryImport(Library)] internal static partial int stillroom_store_is_old_format(IntPtr store, [MarshalAs(UnmanagedType.U1)] out bool result);
    [LibraryImport(Library)] internal static partial int stillroom_store_is_locked_to_a_mac(IntPtr store, [MarshalAs(UnmanagedType.U1)] out bool result);
    [LibraryImport(Library)] internal static partial int stillroom_store_create(IntPtr store, byte* password, nuint length, out IntPtr vault, out IntPtr recoveryKey);
    [LibraryImport(Library)] internal static partial int stillroom_store_unlock_with_password(IntPtr store, byte* password, nuint length, out IntPtr vault);
    [LibraryImport(Library)] internal static partial int stillroom_store_unlock_with_recovery_key(IntPtr store, byte* key, nuint length, out IntPtr vault);
    [LibraryImport(Library)] internal static partial int stillroom_store_unlock_with_kit(IntPtr store, byte* pieces, nuint length, out IntPtr vault);
    [LibraryImport(Library)] internal static partial int stillroom_store_record_intruder(IntPtr store, int kind, byte* photo, nuint length);
    [LibraryImport(Library)] internal static partial int stillroom_store_wait_before_next_try(IntPtr store, out ulong seconds);
    [LibraryImport(Library)] internal static partial int stillroom_store_count_wrong_try(IntPtr store);
    [LibraryImport(Library)] internal static partial int stillroom_store_clear_wrong_tries(IntPtr store);
    [LibraryImport(Library, StringMarshalling = StringMarshalling.Utf8)] internal static partial int stillroom_store_backup(IntPtr store, string to);
    [LibraryImport(Library, StringMarshalling = StringMarshalling.Utf8)] internal static partial int stillroom_store_restore(IntPtr store, string file, out IntPtr setAside);
    [LibraryImport(Library, StringMarshalling = StringMarshalling.Utf8)] internal static partial int stillroom_backup_check(string file);

    // Open vaults
    [LibraryImport(Library)] internal static partial void stillroom_vault_lock(IntPtr vault);
    [LibraryImport(Library)] internal static partial int stillroom_vault_state(VaultHandle vault, out IntPtr result);
    [LibraryImport(Library, StringMarshalling = StringMarshalling.Utf8)] internal static partial int stillroom_vault_add(VaultHandle vault, string paths, string? folder, out IntPtr result);
    [LibraryImport(Library, StringMarshalling = StringMarshalling.Utf8)] internal static partial int stillroom_delete_originals(string originals, out IntPtr result);
    [LibraryImport(Library, StringMarshalling = StringMarshalling.Utf8)] internal static partial int stillroom_originals_removals(string originals, out IntPtr result);
    [LibraryImport(Library, StringMarshalling = StringMarshalling.Utf8)] internal static partial int stillroom_vault_add_data(VaultHandle vault, byte* data, nuint length, string name, string? folder, out IntPtr result);
    [LibraryImport(Library, StringMarshalling = StringMarshalling.Utf8)] internal static partial int stillroom_vault_new_entry(VaultHandle vault, int kind, string name, byte* content, nuint length, string? folder, out IntPtr result);
    [LibraryImport(Library, StringMarshalling = StringMarshalling.Utf8)] internal static partial int stillroom_vault_read(VaultHandle vault, string item, string? version, out StillroomBytes result);
    [LibraryImport(Library, StringMarshalling = StringMarshalling.Utf8)] internal static partial int stillroom_vault_export_item(VaultHandle vault, string item, string to);
    [LibraryImport(Library, StringMarshalling = StringMarshalling.Utf8)] internal static partial int stillroom_vault_export_all(VaultHandle vault, string parent, out IntPtr result);
    [LibraryImport(Library, StringMarshalling = StringMarshalling.Utf8)] internal static partial int stillroom_vault_delete(VaultHandle vault, string item);
    [LibraryImport(Library, StringMarshalling = StringMarshalling.Utf8)] internal static partial int stillroom_vault_update(VaultHandle vault, string item, byte* data, nuint length, string? name);
    [LibraryImport(Library, StringMarshalling = StringMarshalling.Utf8)] internal static partial int stillroom_vault_update_from_file(VaultHandle vault, string item, string file);
    [LibraryImport(Library, StringMarshalling = StringMarshalling.Utf8)] internal static partial int stillroom_vault_restore_version(VaultHandle vault, string item, string version);
    [LibraryImport(Library, StringMarshalling = StringMarshalling.Utf8)] internal static partial int stillroom_vault_drop_version(VaultHandle vault, string item, string version);
    [LibraryImport(Library, StringMarshalling = StringMarshalling.Utf8)] internal static partial int stillroom_vault_fall_back(VaultHandle vault, string item, string version);
    [LibraryImport(Library)] internal static partial int stillroom_vault_check(VaultHandle vault, out IntPtr result);
    [LibraryImport(Library, StringMarshalling = StringMarshalling.Utf8)] internal static partial int stillroom_vault_rename(VaultHandle vault, string item, string name);
    [LibraryImport(Library, StringMarshalling = StringMarshalling.Utf8)] internal static partial int stillroom_vault_set_tags(VaultHandle vault, string item, string tags);
    [LibraryImport(Library, StringMarshalling = StringMarshalling.Utf8)] internal static partial int stillroom_vault_make_folder(VaultHandle vault, string name, string? parent);
    [LibraryImport(Library, StringMarshalling = StringMarshalling.Utf8)] internal static partial int stillroom_vault_move_items(VaultHandle vault, string items, string? folder);
    [LibraryImport(Library, StringMarshalling = StringMarshalling.Utf8)] internal static partial int stillroom_vault_rename_folder(VaultHandle vault, string folder, string name, out IntPtr result);
    [LibraryImport(Library, StringMarshalling = StringMarshalling.Utf8)] internal static partial int stillroom_vault_move_folder(VaultHandle vault, string folder, string? into);
    [LibraryImport(Library, StringMarshalling = StringMarshalling.Utf8)] internal static partial int stillroom_vault_delete_folder(VaultHandle vault, string folder);
    [LibraryImport(Library)] internal static partial int stillroom_vault_set_show_in_capture(VaultHandle vault, [MarshalAs(UnmanagedType.U1)] bool on);

    // Keys
    [LibraryImport(Library)] internal static partial int stillroom_vault_change_password(VaultHandle vault, byte* current, nuint currentLength, byte* next, nuint nextLength);
    [LibraryImport(Library)] internal static partial int stillroom_vault_set_password_after_recovery(VaultHandle vault, byte* next, nuint length);
    [LibraryImport(Library)] internal static partial int stillroom_vault_set_other_slot(VaultHandle vault, byte* password, nuint length, out IntPtr recoveryKey);
    [LibraryImport(Library)] internal static partial int stillroom_vault_reset_other_slot(VaultHandle vault);
    [LibraryImport(Library)] internal static partial int stillroom_vault_new_recovery_key(VaultHandle vault, out IntPtr recoveryKey);
    [LibraryImport(Library)] internal static partial int stillroom_vault_make_kit(VaultHandle vault, byte threshold, byte count, out IntPtr pieces);
    [LibraryImport(Library)] internal static partial int stillroom_vault_remove_kit(VaultHandle vault);
    [LibraryImport(Library)] internal static partial int stillroom_vault_kit_reminder_due(VaultHandle vault, [MarshalAs(UnmanagedType.U1)] out bool result);

    // Intruders, search, import
    [LibraryImport(Library)] internal static partial int stillroom_vault_intruders(VaultHandle vault, out IntPtr result);
    [LibraryImport(Library, StringMarshalling = StringMarshalling.Utf8)] internal static partial int stillroom_vault_delete_intruder(VaultHandle vault, string entry);
    [LibraryImport(Library)] internal static partial int stillroom_vault_clear_intruders(VaultHandle vault);
    [LibraryImport(Library)] internal static partial int stillroom_vault_refresh_search(VaultHandle vault, delegate* unmanaged<IntPtr, byte*, byte*, nuint, byte*> readText, IntPtr context, [MarshalAs(UnmanagedType.U1)] out bool changed);
    [LibraryImport(Library, StringMarshalling = StringMarshalling.Utf8)] internal static partial int stillroom_vault_search(VaultHandle vault, string query, out IntPtr result);
    [LibraryImport(Library, StringMarshalling = StringMarshalling.Utf8)] internal static partial int stillroom_vault_snippet(VaultHandle vault, string item, string query, out IntPtr result);
    [LibraryImport(Library)] internal static partial int stillroom_vault_import_logins(VaultHandle vault, byte* csv, nuint length, out IntPtr result);

    // Backups and endings
    [LibraryImport(Library, StringMarshalling = StringMarshalling.Utf8)] internal static partial int stillroom_vault_backup(VaultHandle vault, string to);
    [LibraryImport(Library, StringMarshalling = StringMarshalling.Utf8)] internal static partial int stillroom_vault_restore_backup(IntPtr vault, string file, out IntPtr setAside);
    [LibraryImport(Library)] internal static partial int stillroom_vault_wipe(IntPtr vault);

    // Playing audio and video
    [LibraryImport(Library, StringMarshalling = StringMarshalling.Utf8)] internal static partial int stillroom_vault_open_reader(VaultHandle vault, string item, out IntPtr reader, out ulong size);
    [LibraryImport(Library)] internal static partial int stillroom_reader_read(IntPtr reader, ulong offset, byte* buffer, nuint capacity, out nuint read);
    [LibraryImport(Library)] internal static partial void stillroom_reader_free(IntPtr reader);

    // Without a vault
    [LibraryImport(Library)] internal static partial int stillroom_password_strength(byte* password, nuint length, out double bits, [MarshalAs(UnmanagedType.U1)] out bool enough);
    [LibraryImport(Library, StringMarshalling = StringMarshalling.Utf8)] internal static partial int stillroom_one_time_code(string label, byte* value, nuint length, double unixSeconds, out IntPtr code, out ulong secondsLeft);
    [LibraryImport(Library, StringMarshalling = StringMarshalling.Utf8)] internal static partial int stillroom_uti_for_name(string name, out IntPtr result);
    [LibraryImport(Library, StringMarshalling = StringMarshalling.Utf8)] internal static partial int stillroom_look(string uti, out byte result);
    [LibraryImport(Library, StringMarshalling = StringMarshalling.Utf8)] internal static partial int stillroom_can_edit(string uti, string name, [MarshalAs(UnmanagedType.U1)] bool isFile, [MarshalAs(UnmanagedType.U1)] out bool result);
    [LibraryImport(Library)] internal static partial int stillroom_email_read(byte* data, nuint length, out IntPtr result);
    [LibraryImport(Library)] internal static partial int stillroom_email_attachment(byte* data, nuint length, nuint index, out StillroomBytes result);
}
