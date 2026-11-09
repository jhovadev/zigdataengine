//! Narrow std.Io boundary. Adapt this module when Zig changes its I/O API.
//! This module deliberately exposes only the operations we currently need.
const std = @import("std");

pub const Reader = std.Io.Reader;
pub const Writer = std.Io.Writer;
pub const ReadError = std.Io.Reader.ShortError;
pub const WriteError = std.Io.Writer.Error;

/// Short read occurs only at end of stream for std.Io.Reader.readSliceShort.
pub fn readSome(reader: *Reader, destination: []u8) ReadError!usize {
    return reader.readSliceShort(destination);
}

pub fn writeAll(writer: *Writer, bytes: []const u8) WriteError!void {
    return writer.writeAll(bytes);
}

pub fn flush(writer: *Writer) WriteError!void {
    return writer.flush();
}
