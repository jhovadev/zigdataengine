//! Demonstrates use of the SDK with the std.Io file adapters.
//! The destination must not already exist; accidental overwrite is refused.
const std = @import("std");
const zdata = @import("zdata");

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len != 3) {
        std.debug.print("Usage: zdata-copy <source> <new-destination>\n", .{});
        return error.InvalidArguments;
    }
    if (std.mem.eql(u8, args[1], args[2])) return error.SameSourceAndDestination;

    const input = try std.Io.Dir.cwd().openFile(io, args[1], .{});
    defer input.close(io);
    const output = try std.Io.Dir.cwd().createFile(io, args[2], .{ .exclusive = true });
    defer output.close(io);

    var reader_buffer: [64 * 1024]u8 = undefined;
    var writer_buffer: [64 * 1024]u8 = undefined;
    var transfer_buffer: [256 * 1024]u8 = undefined;
    var in_reader = input.reader(io, &reader_buffer);
    var out_writer = output.writer(io, &writer_buffer);

    const stats = try zdata.transfer.copy(
        &in_reader.interface,
        &out_writer.interface,
        &transfer_buffer,
        .{},
    );
    std.debug.print("Copied {d} bytes\n", .{stats.bytes_copied});
}
