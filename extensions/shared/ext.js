// Stellar Download Manager — Browser API namespace
// Copyright (C) 2026 Ninka_
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program. If not, see <https://www.gnu.org/licenses/>.

// Firefox exposes promise-returning `browser.*`; Chrome MV3 returns promises from
// `chrome.*` when no callback is passed. Every shared module goes through this one
// binding so the same code runs unmodified in both browsers.
export const ext = globalThis.browser ?? globalThis.chrome;

