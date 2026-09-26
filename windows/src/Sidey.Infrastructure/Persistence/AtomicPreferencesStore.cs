using System.Text.Json;
using System.Text.Json.Serialization;
using Sidey.Core.Abstractions;
using Sidey.Core.Domain;
using Sidey.Core.Localization;

namespace Sidey.Infrastructure.Persistence;

public sealed class AtomicPreferencesStore : IPreferencesStore
{
    private static readonly JsonSerializerOptions s_serializerOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        PropertyNameCaseInsensitive = true,
        WriteIndented = true,
        Converters = { new JsonStringEnumConverter(JsonNamingPolicy.CamelCase) },
    };

    private readonly string _path;
    private readonly SemaphoreSlim _gate = new(1, 1);

    public AtomicPreferencesStore(string? path = null)
    {
        _path = path ?? Path.Combine(
            Sidey.Core.Storage.SideyStoragePaths.LocalApplicationDataRoot(),
            "SIDEY",
            "preferences.json");
    }

    public async ValueTask<AppPreferences> LoadAsync(CancellationToken cancellationToken = default)
    {
        await _gate.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            if (!File.Exists(_path))
            {
                return AppPreferences.CreateDefault();
            }

            await using var stream = new FileStream(
                _path,
                FileMode.Open,
                FileAccess.Read,
                FileShare.Read,
                bufferSize: 4096,
                FileOptions.Asynchronous | FileOptions.SequentialScan);
            AppPreferences? preferences = await JsonSerializer.DeserializeAsync<AppPreferences>(
                stream,
                s_serializerOptions,
                cancellationToken).ConfigureAwait(false);
            return preferences?.Normalize() ?? AppPreferences.CreateDefault();
        }
        catch (JsonException exception)
        {
            throw new InvalidDataException(I18n.Get("settings.storage.read_failed"), exception);
        }
        finally
        {
            _gate.Release();
        }
    }

    public async ValueTask SaveAsync(
        AppPreferences preferences,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(preferences);
        await _gate.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            string directory = Path.GetDirectoryName(_path)
                ?? throw new InvalidOperationException(I18n.Get("settings.storage.folder_invalid"));
            Directory.CreateDirectory(directory);
            string temporaryPath = Path.Combine(
                directory,
                $".{Path.GetFileName(_path)}.{Guid.NewGuid():N}.tmp");
            try
            {
                await using (var stream = new FileStream(
                    temporaryPath,
                    FileMode.CreateNew,
                    FileAccess.Write,
                    FileShare.None,
                    bufferSize: 4096,
                    FileOptions.Asynchronous | FileOptions.WriteThrough))
                {
                    await JsonSerializer.SerializeAsync(
                        stream,
                        preferences.Normalize(),
                        s_serializerOptions,
                        cancellationToken).ConfigureAwait(false);
                    await stream.FlushAsync(cancellationToken).ConfigureAwait(false);
                }

                File.Move(temporaryPath, _path, overwrite: true);
            }
            finally
            {
                if (File.Exists(temporaryPath))
                {
                    File.Delete(temporaryPath);
                }
            }
        }
        finally
        {
            _gate.Release();
        }
    }
}
