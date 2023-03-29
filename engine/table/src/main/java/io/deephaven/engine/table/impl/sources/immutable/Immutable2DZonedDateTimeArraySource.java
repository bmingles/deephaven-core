/**
 * Copyright (c) 2016-2023 Deephaven Data Labs and Patent Pending
 */
package io.deephaven.engine.table.impl.sources.immutable;

import io.deephaven.engine.table.ColumnSource;
import io.deephaven.engine.table.impl.ImmutableColumnSourceGetDefaults;
import io.deephaven.engine.table.impl.sources.ConvertableTimeSource;
import io.deephaven.time.DateTimeUtils;
import org.jetbrains.annotations.NotNull;

import java.time.ZoneId;
import java.time.ZonedDateTime;

/**
 * ImmutableArraySource for {@link ZonedDateTime}s. Allows reinterpretation as long.
 */
public class Immutable2DZonedDateTimeArraySource extends Immutable2DNanosBasedTimeArraySource<ZonedDateTime>
        implements ImmutableColumnSourceGetDefaults.ForObject<ZonedDateTime>, ConvertableTimeSource.Zoned {
    private final ZoneId zone;

    public Immutable2DZonedDateTimeArraySource(
            final @NotNull ZoneId zone) {
        super(ZonedDateTime.class);
        this.zone = zone;
    }

    public Immutable2DZonedDateTimeArraySource(
            final @NotNull ZoneId zone,
            final @NotNull Immutable2DLongArraySource nanoSource) {
        super(ZonedDateTime.class, nanoSource);
        this.zone = zone;
    }

    @Override
    protected ZonedDateTime makeValue(long nanos) {
        return DateTimeUtils.makeZonedDateTime(nanos, zone);
    }

    @Override
    protected long toNanos(ZonedDateTime value) {
        return DateTimeUtils.toEpochNano(value);
    }

    @Override
    public ColumnSource<ZonedDateTime> toZonedDateTime(final @NotNull ZoneId zone) {
        if (this.zone.equals(zone)) {
            return this;
        }

        return new Immutable2DZonedDateTimeArraySource(zone, this.nanoSource);
    }

    @Override
    public ZoneId getZone() {
        return zone;
    }
}