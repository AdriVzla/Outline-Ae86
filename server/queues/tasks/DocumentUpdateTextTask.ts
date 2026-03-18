import { Node } from "prosemirror-model";
import { schema, serializer } from "@server/editor";
import { Document } from "@server/models";
import type { DocumentEvent } from "@server/types";
import { DocumentHelper } from "@server/models/helpers/DocumentHelper";
import { BaseTask } from "./base/BaseTask";

interface Iso6393Module {
  iso6393To1: Record<string, string | undefined>;
}

interface FrancModule {
  franc: (
    text: string,
    options?: {
      minLength?: number;
    }
  ) => string;
}

let iso6393Module: Promise<Iso6393Module> | undefined;
let francModule: Promise<FrancModule> | undefined;

const getIso6393Module = () => {
  if (!iso6393Module) {
    iso6393Module = import("iso-639-3") as Promise<Iso6393Module>;
  }

  return iso6393Module;
};

const getFrancModule = () => {
  if (!francModule) {
    francModule = import("franc") as Promise<FrancModule>;
  }

  return francModule;
};

export default class DocumentUpdateTextTask extends BaseTask<DocumentEvent> {
  public async perform(event: DocumentEvent) {
    const document = await Document.findByPk(event.documentId);
    if (!document?.content) {
      return;
    }

    const node = Node.fromJSON(schema, document.content);
    document.text = serializer.serialize(node);

    const { franc } = await getFrancModule();
    const language = franc(DocumentHelper.toPlainText(document), {
      minLength: 50,
    });
    const { iso6393To1 } = await getIso6393Module();
    document.language = iso6393To1[language];

    await document.save({ silent: true });
  }
}
