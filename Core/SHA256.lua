-- Pure-Lua SHA-256 (WoW's Lua 5.1 + bit library). Used for shuffle commitments and the deck RNG.
-- Works whether the bit library returns signed or unsigned 32-bit values: everything is
-- normalised with `% 2^32` before it is added or printed.
local _, ns = ...

local bit = bit
local band, bor, bxor, bnot, rshift, lshift = bit.band, bit.bor, bit.bxor, bit.bnot, bit.rshift, bit.lshift
local floor, char, byte, format = math.floor, string.char, string.byte, string.format

local MOD = 4294967296
local function u(x) return x % MOD end
local function rrot(x, n) return u(bor(rshift(x, n), lshift(x, 32 - n))) end
local function x3(a, b, c) return u(bxor(bxor(a, b), c)) end

local K = {
	0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
	0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
	0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
	0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
	0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
	0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
	0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
	0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
}
local H0 = { 0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19 }

local function be32(x)
	return char(floor(x / 16777216) % 256, floor(x / 65536) % 256, floor(x / 256) % 256, x % 256)
end

local w = {}
--- Returns the SHA-256 digest of `msg` as 64 lowercase hex characters.
function ns.SHA256(msg)
	msg = tostring(msg)
	local len = #msg
	local bits = len * 8
	msg = msg .. "\128" .. string.rep("\0", (55 - len) % 64) .. be32(floor(bits / MOD)) .. be32(bits % MOD)

	local H = { H0[1], H0[2], H0[3], H0[4], H0[5], H0[6], H0[7], H0[8] }
	for chunk = 1, #msg, 64 do
		for i = 0, 15 do
			local a, b, c, d = byte(msg, chunk + i * 4, chunk + i * 4 + 3)
			w[i] = ((a * 256 + b) * 256 + c) * 256 + d
		end
		for i = 16, 63 do
			local v0, v1 = w[i - 15], w[i - 2]
			local s0 = x3(rrot(v0, 7), rrot(v0, 18), u(rshift(v0, 3)))
			local s1 = x3(rrot(v1, 17), rrot(v1, 19), u(rshift(v1, 10)))
			w[i] = u(w[i - 16] + s0 + w[i - 7] + s1)
		end
		local a, b, c, d, e, f, g, h = H[1], H[2], H[3], H[4], H[5], H[6], H[7], H[8]
		for i = 0, 63 do
			local S1 = x3(rrot(e, 6), rrot(e, 11), rrot(e, 25))
			local ch = u(bxor(band(e, f), band(bnot(e), g)))
			local t1 = u(h + S1 + ch + K[i + 1] + w[i])
			local S0 = x3(rrot(a, 2), rrot(a, 13), rrot(a, 22))
			local maj = x3(u(band(a, b)), u(band(a, c)), u(band(b, c)))
			h, g, f, e, d, c, b, a = g, f, e, u(d + t1), c, b, a, u(t1 + S0 + maj)
		end
		H[1], H[2], H[3], H[4] = u(H[1] + a), u(H[2] + b), u(H[3] + c), u(H[4] + d)
		H[5], H[6], H[7], H[8] = u(H[5] + e), u(H[6] + f), u(H[7] + g), u(H[8] + h)
	end
	local out = {}
	for i = 1, 8 do
		-- split into 16-bit halves: %x on a 32-bit value can overflow a C `long` on Windows
		out[i] = format("%04x%04x", floor(H[i] / 65536), H[i] % 65536)
	end
	return table.concat(out)
end
