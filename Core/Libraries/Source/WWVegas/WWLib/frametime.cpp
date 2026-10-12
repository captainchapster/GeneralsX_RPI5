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

#include "frametime.h"

#ifdef _WIN32
#include <windows.h>
#else
#include <time.h>
#endif

namespace
{
	double s_partSeconds[FrameTime::PART_COUNT] = {0};
}

double FrameTime::Now()
{
#ifdef _WIN32
	LARGE_INTEGER frequency;
	LARGE_INTEGER counter;
	QueryPerformanceFrequency(&frequency);
	QueryPerformanceCounter(&counter);
	return (double)counter.QuadPart / (double)frequency.QuadPart;
#else
	struct timespec now;
	clock_gettime(CLOCK_MONOTONIC, &now);
	return (double)now.tv_sec + (double)now.tv_nsec * 1e-9;
#endif
}

void FrameTime::Add(Part part, double seconds)
{
	s_partSeconds[part] += seconds;
}

double FrameTime::Take(Part part)
{
	const double seconds = s_partSeconds[part];
	s_partSeconds[part] = 0.0;
	return seconds;
}
