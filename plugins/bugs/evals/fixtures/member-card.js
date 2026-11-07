// Renders one workspace member as an HTML string for the team page.
// `member` comes from GET /api/members: { name, email, avatarUrl, projectCount }.

export function initials(name) {
  return name.split(" ")[0][0] + name.split(" ")[1][0];
}

export function renderMemberCard(member) {
  const projects = member.projectCount + " projects";
  return `
    <article class="member">
      <img class="avatar" src="${member.avatarUrl}" alt="">
      <span class="initials">${initials(member.name)}</span>
      <h3>${member.name}</h3>
      <p>${member.email}</p>
      <p class="count">${projects}</p>
    </article>`;
}
