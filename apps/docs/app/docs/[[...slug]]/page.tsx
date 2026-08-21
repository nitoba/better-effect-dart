import { getPageImageUrl, getPageMarkdownUrl, source } from '@/lib/source';
import {
  DocsBody,
  DocsDescription,
  DocsPage,
  DocsTitle,
} from '@/layouts/flux/page';
import { MarkdownCopyButton, ViewOptionsPopover } from '@/components/ai/page-actions';
import { InlineTOC } from '@/components/inline-toc';
import { notFound } from 'next/navigation';
import { getMDXComponents } from '@/components/mdx';
import type { Metadata } from 'next';
import { createRelativeLink } from 'fumadocs-ui/mdx';
import { appName, gitConfig } from '@/lib/shared';

export default async function Page(props: PageProps<'/docs/[[...slug]]'>) {
  const params = await props.params;
  const page = source.getPage(params.slug);
  if (!page) notFound();

  const MDX = page.data.body;
  const markdownUrl = getPageMarkdownUrl(page).url;
  const isSectionIndex = page.path === 'index.mdx' || page.path.endsWith('/index.mdx');
  const hasInlineToc = page.data.toc.length >= 2;
  const isGuide = page.path.startsWith('guides/') || page.path.startsWith('getting-started/');

  return (
    <DocsPage toc={page.data.toc} full={page.data.full} breadcrumb={{ enabled: !isSectionIndex }}>
      <DocsTitle>{page.data.title}</DocsTitle>
      <DocsDescription className="mb-0">{page.data.description}</DocsDescription>
      <div className="flex flex-row gap-2 items-center border-b pb-6">
        <MarkdownCopyButton markdownUrl={markdownUrl} />
        <ViewOptionsPopover
          markdownUrl={markdownUrl}
          githubUrl={`https://github.com/${gitConfig.user}/${gitConfig.repo}/blob/${gitConfig.branch}/content/docs/${page.path}`}
        />
      </div>
      {hasInlineToc && (
        <InlineTOC
          items={page.data.toc}
          defaultOpen={isGuide}
          className="be-inline-toc xl:hidden"
        >
          {isGuide ? 'Roteiro deste guia' : 'Nesta página'}
        </InlineTOC>
      )}
      <DocsBody>
        <MDX
          components={getMDXComponents({
            a: createRelativeLink(source, page),
          })}
        />
      </DocsBody>
    </DocsPage>
  );
}

export async function generateStaticParams() {
  return source.generateParams();
}

export async function generateMetadata(props: PageProps<'/docs/[[...slug]]'>): Promise<Metadata> {
  const params = await props.params;
  const page = source.getPage(params.slug);
  if (!page) notFound();

  const imageUrl = getPageImageUrl(page).url;

  return {
    title: page.data.title,
    description: page.data.description,
    alternates: {
      canonical: page.url,
    },
    openGraph: {
      type: 'article',
      url: page.url,
      siteName: appName,
      locale: 'pt_BR',
      title: page.data.title,
      description: page.data.description,
      images: [
        {
          url: imageUrl,
          width: 1200,
          height: 630,
          alt: `${page.data.title} — documentação ${appName}`,
        },
      ],
    },
    twitter: {
      card: 'summary_large_image',
      title: page.data.title,
      description: page.data.description,
      images: [imageUrl],
    },
  };
}
