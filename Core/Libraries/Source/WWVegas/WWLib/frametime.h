/*
**	Command & Conquer Generals Zero Hour(tm)
**	Copyright 2025 Electronic Arts Inc.
**
**	This program is free software: you can redistribute it and/or modify
**	it under the terms of the GNU General Public License as published by
**	the Free Software Foundation, either version 3 of the License, or
**	(at your option) any later version.
**
**	This program is distributed in the hope that it will be useful,
**	but WITHOUT ANY WARRANTY; without even the implied warranty of
**	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
**	GNU General Public License for more details.
**
**	You should have received a copy of the GNU General Public License
**	along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/

// GeneralsX @feature Claude 12/10/2026 Frame time breakdown for the GENERALSX_FPS_LOG console log.
// The main loop adds the time it spends in a few parts of each frame here, and the FPS log in
// W3DDisplay.cpp takes the totals once per frame. Whatever is left of the frame (input, audio,
// network and the client update) is what the log calls "other".

#pragma once

namespace FrameTime
{
	enum Part
	{
		PART_LOGIC,		// GameLogic update (the simulation)
		PART_DRAW,		// W3DDisplay::draw, including PART_PRESENT
		PART_PRESENT,	// end of scene: pillarbox blit and Present, where the CPU waits for the GPU
		PART_PACING,	// frame rate cap sleep
		PART_COUNT
	};

	// Seconds from a monotonic clock.
	double Now();

	void Add(Part part, double seconds);

	// Returns the time added to a part since the last call, and clears it.
	double Take(Part part);

	// Adds the lifetime of the scope to a part.
	class Scope
	{
	public:
		explicit Scope(Part part) : m_part(part), m_start(Now()) {}
		~Scope() { Add(m_part, Now() - m_start); }

	private:
		Part m_part;
		double m_start;
	};
}
