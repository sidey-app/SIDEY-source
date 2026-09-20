namespace Sidey.Core.Domain;

public enum MessageDeliveryState
{
    Pending,
    Confirmed,
    Failed,
}

public sealed record MessageLedgerEntry(
    Guid Id,
    Guid RoomId,
    Guid SenderId,
    string Body,
    DateTimeOffset CreatedAt,
    MessageDeliveryState State,
    string? BubbleStyleId = null);

public sealed class MessageLedger
{
    public const int MaximumConfirmedPerRoom = 50;
    public static readonly TimeSpan ConfirmedRetention = TimeSpan.FromDays(3);

    private readonly List<MessageLedgerEntry> _entries = [];

    public IReadOnlyList<MessageLedgerEntry> Entries => _entries;

    public MessageLedgerEntry? Latest => _entries.LastOrDefault();

    public void Stage(
        Guid id,
        Guid roomId,
        Guid senderId,
        string body,
        DateTimeOffset? createdAt = null,
        string? bubbleStyleId = null)
    {
        if (_entries.Any(entry => entry.Id == id))
        {
            return;
        }

        _entries.Add(new MessageLedgerEntry(
            id,
            roomId,
            senderId,
            body,
            createdAt ?? DateTimeOffset.UtcNow,
            MessageDeliveryState.Pending,
            CosmeticCatalog.NormalizeBubbleStyleId(bubbleStyleId)));
    }

    public bool Confirm(ChatMessage message, DateTimeOffset? now = null)
    {
        int index = _entries.FindIndex(entry => entry.Id == message.Id);
        bool wasKnown = index >= 0;
        var confirmed = new MessageLedgerEntry(
            message.Id,
            message.RoomId,
            message.SenderId,
            message.Body,
            message.CreatedAt,
            MessageDeliveryState.Confirmed,
            CosmeticCatalog.NormalizeBubbleStyleId(message.BubbleStyleId));

        if (wasKnown)
        {
            _entries[index] = confirmed;
        }
        else
        {
            _entries.Add(confirmed);
        }

        SortEntries();
        PruneConfirmed(now);
        return !wasKnown;
    }

    public void ReplaceConfirmed(Guid roomId, IEnumerable<ChatMessage> messages)
    {
        _entries.RemoveAll(entry => entry.RoomId == roomId && entry.State == MessageDeliveryState.Confirmed);
        foreach (ChatMessage? message in messages.Where(message => message.RoomId == roomId))
        {
            Confirm(message);
        }
    }

    public string? Fail(Guid id)
    {
        int index = _entries.FindIndex(entry => entry.Id == id && entry.State == MessageDeliveryState.Pending);
        if (index < 0)
        {
            return null;
        }

        string body = _entries[index].Body;
        _entries[index] = _entries[index] with { State = MessageDeliveryState.Failed };
        return body;
    }

    public bool Remove(Guid roomId, Guid messageId) =>
        _entries.RemoveAll(entry => entry.RoomId == roomId && entry.Id == messageId) > 0;

    public void Clear() => _entries.Clear();

    public MessageLedgerEntry? LatestIn(Guid roomId) =>
        _entries.LastOrDefault(entry => entry.RoomId == roomId);

    public void PruneConfirmed(DateTimeOffset? now = null)
    {
        DateTimeOffset cutoff = (now ?? DateTimeOffset.UtcNow) - ConfirmedRetention;
        _entries.RemoveAll(entry =>
            entry.State == MessageDeliveryState.Confirmed && entry.CreatedAt < cutoff);
        foreach (IGrouping<Guid, MessageLedgerEntry>? room in _entries
            .Where(entry => entry.State == MessageDeliveryState.Confirmed)
            .GroupBy(entry => entry.RoomId)
            .ToArray())
        {
            int excess = room.Count() - MaximumConfirmedPerRoom;
            if (excess <= 0)
            {
                continue;
            }

            var remove = room.Take(excess).Select(entry => entry.Id).ToHashSet();
            _entries.RemoveAll(entry =>
                entry.RoomId == room.Key
                && entry.State == MessageDeliveryState.Confirmed
                && remove.Contains(entry.Id));
        }
    }

    private void SortEntries() => _entries.Sort(static (left, right) =>
    {
        int dateComparison = left.CreatedAt.CompareTo(right.CreatedAt);
        return dateComparison != 0
            ? dateComparison
            : StringComparer.Ordinal.Compare(left.Id.ToString("D"), right.Id.ToString("D"));
    });
}

public sealed class ActiveBubbleLedger
{
    public const int MaximumVisiblePerSender = 2;
    public static readonly TimeSpan DefaultLifetime = TimeSpan.FromSeconds(10);

    private readonly List<ActiveBubble> _bubbles = [];

    public IReadOnlyList<ActiveBubble> Bubbles => _bubbles;

    public void Show(
        Guid senderId,
        Guid messageId,
        string body,
        DateTimeOffset? expiresAt = null,
        string? bubbleStyleId = null)
    {
        _bubbles.RemoveAll(bubble => bubble.MessageId == messageId);
        _bubbles.Add(new ActiveBubble(
            senderId,
            messageId,
            body,
            expiresAt ?? DateTimeOffset.UtcNow.Add(DefaultLifetime),
            CosmeticCatalog.NormalizeBubbleStyleId(bubbleStyleId)));
        _bubbles.Sort(static (left, right) =>
        {
            int dateComparison = left.ExpiresAt.CompareTo(right.ExpiresAt);
            return dateComparison != 0
                ? dateComparison
                : StringComparer.Ordinal.Compare(left.MessageId.ToString("D"), right.MessageId.ToString("D"));
        });

        ActiveBubble[] senderBubbles = [.. _bubbles.Where(bubble => bubble.SenderId == senderId)];
        if (senderBubbles.Length > MaximumVisiblePerSender)
        {
            var removedIds = senderBubbles
                .Take(senderBubbles.Length - MaximumVisiblePerSender)
                .Select(bubble => bubble.MessageId)
                .ToHashSet();
            _bubbles.RemoveAll(bubble => removedIds.Contains(bubble.MessageId));
        }
    }

    public void Remove(Guid messageId) =>
        _bubbles.RemoveAll(bubble => bubble.MessageId == messageId);

    public void Clear() => _bubbles.Clear();

    public void Prune(DateTimeOffset? date = null)
    {
        DateTimeOffset cutoff = date ?? DateTimeOffset.UtcNow;
        _bubbles.RemoveAll(bubble => bubble.ExpiresAt <= cutoff);
    }
}
