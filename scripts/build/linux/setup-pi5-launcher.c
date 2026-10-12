/*
 * GeneralsX @build rpi5 12/10/2026
 * "Setup" program of the Raspberry Pi 5 package: runs setup-pi5-zh.sh from its .setup folder
 * (in the package) or from its own folder (once installed).
 *
 * File managers such as Thunar open a double-clicked shell script in a text editor, even when it
 * is executable, but run a double-clicked program. This small program is what the package ships
 * as Setup, so a double click starts the Setup wizard. bundle-pi5-zh.sh builds it with -no-pie,
 * because some file managers treat position-independent executables as libraries.
 */
#include <libgen.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

int main(int argc, char **argv)
{
	char self[PATH_MAX];
	ssize_t length = readlink("/proc/self/exe", self, sizeof(self) - 1);
	if (length < 0) {
		perror("Setup: cannot find its own folder");
		return 1;
	}
	self[length] = '\0';

	/* The package keeps the scripts in a hidden .setup folder; the installed copy keeps them
	 * next to Setup. */
	const char *folder = dirname(self);
	char script[PATH_MAX];
	if (snprintf(script, sizeof(script), "%s/.setup/setup-pi5-zh.sh", folder) >= (int)sizeof(script)) {
		fprintf(stderr, "Setup: folder path too long\n");
		return 1;
	}
	if (access(script, R_OK) != 0) {
		snprintf(script, sizeof(script), "%s/setup-pi5-zh.sh", folder);
	}

	char **args = calloc((size_t)argc + 2, sizeof(char *));
	if (args == NULL) {
		perror("Setup");
		return 1;
	}
	args[0] = "bash";
	args[1] = script;
	for (int i = 1; i < argc; ++i) {
		args[i + 1] = argv[i];
	}
	execvp("bash", args);
	perror("Setup: cannot run bash");
	return 1;
}
