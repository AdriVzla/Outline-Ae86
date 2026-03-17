const client = getClientFromOAuthState(context);
const user =
  context.state?.auth?.user ?? (await getUserFromOAuthState(context));

// No profile domain means personal gmail account
// No team implies the request came from the apex domain
// This combination is always an error
if (!domain && !team) {
  const userExists = await User.count({
    where: { email: profile.email.toLowerCase() },
    include: [
      {
        association: "team",
        required: true,
      },
    ],
  });

  // Users cannot create a team with personal gmail accounts
  if (!userExists) {
    // throw GmailAccountCreationError();
  }

  // To log-in with a personal account, users must specify a team subdomain
  // throw TeamDomainRequiredError();
}

// remove the TLD and form a subdomain from the remaining
// subdomains of the form "foo.bar.com" are allowed as primary Google Workspaces domains
// see https://support.google.com/nonprofits/thread/19685140/using-a-subdomain-as-a-primary-domain
